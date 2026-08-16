require "./base"
require "./client_configuration"
require "./errors"
require "./item_operations"

# One item of a transactional read, with the model its result is built into.
struct Aws::Record::TransactGetItemRequest
  # The model the item is built into.
  getter model_class : Aws::Record::Base.class

  # The read itself.
  getter get : Aws::DynamoDB::Types::Get

  # Creates a read request.
  def initialize(@model_class : Aws::Record::Base.class, @get : Aws::DynamoDB::Types::Get) : Nil
  end
end

# One item of a transactional write, plus what to do with its record once the transaction succeeds.
struct Aws::Record::TransactWriteAction
  # The write itself.
  getter item : Aws::DynamoDB::Types::TransactWriteItem

  # The record to mark clean once the transaction succeeds.
  getter clean_after : Aws::Record::Base?

  # The record to mark destroyed once the transaction succeeds.
  getter destroy_after : Aws::Record::Base?

  # Creates a write action.
  def initialize(@item : Aws::DynamoDB::Types::TransactWriteItem,
                 @clean_after : Aws::Record::Base? = nil,
                 @destroy_after : Aws::Record::Base? = nil) : Nil
  end
end

# An item of a transactional read that was not there.
struct Aws::Record::MissingItem
  # The model the item would have been built into.
  getter model_class : Aws::Record::Base.class

  # The key that was asked for.
  getter key : Aws::DynamoDB::Item

  # Creates a missing item.
  def initialize(@model_class : Aws::Record::Base.class, @key : Aws::DynamoDB::Item) : Nil
  end
end

# The result of `Aws::Record::Transactions.transact_find`.
#
# `#responses` has one entry per requested item, in order, and `nil` where an item was not found;
# those are listed in `#missing_items`.
struct Aws::Record::TransactFindResult
  # One entry per requested item, `nil` where the item was not found.
  getter responses : Array(Aws::Record::Base?)

  # The items that were not found.
  getter missing_items : Array(Aws::Record::MissingItem)

  # The capacity the transaction consumed, when it was asked for.
  getter consumed_capacity : Array(Aws::DynamoDB::Types::ConsumedCapacity)?

  # Creates a result.
  def initialize(@responses : Array(Aws::Record::Base?), @missing_items : Array(Aws::Record::MissingItem),
                 @consumed_capacity : Array(Aws::DynamoDB::Types::ConsumedCapacity)?) : Nil
  end
end

# Transactional reads and writes across tables and models.
#
# ```
# Aws::Record::Transactions.transact_write(transact_items: [
#   Aws::Record::Transactions.save(post),
#   Aws::Record::Transactions.delete(old_post),
#   Aws::Record::Transactions.check(Forum.transact_check_expression(key: {forum_uuid: "a"}, ...)),
# ])
# ```
#
# Where the Ruby gem takes a hash per item (`{save: record}`), each item here is built by one of
# `.save`, `.put`, `.update`, `.delete` or `.check`, so the operation and its options are checked at
# compile time.
class Aws::Record::Transactions
  extend Aws::Record::ClientConfiguration

  # Reads several items in one transaction, building each into the model it was asked for.
  def self.transact_find(transact_items : Array(Aws::Record::TransactGetItemRequest),
                         client : Aws::DynamoDB::Client? = nil, **opts) : Aws::Record::TransactFindResult
    input = Aws::DynamoDB::Types::TransactGetItemsInput.new(**opts).merge(
      transact_items: transact_items.map { |request| Aws::DynamoDB::Types::TransactGetItem.new(get: request.get) }
    )
    response = (client || dynamodb_client).transact_get_items(input)
    build_find_result(transact_items, response)
  end

  # Writes several items in one transaction.
  #
  # Every record that was saved, put or updated is marked clean, and every deleted one destroyed,
  # once the transaction has succeeded — and only then.
  def self.transact_write(transact_items : Array(Aws::Record::TransactWriteAction),
                          client : Aws::DynamoDB::Client? = nil,
                          **opts) : Aws::DynamoDB::Types::TransactWriteItemsOutput
    input = Aws::DynamoDB::Types::TransactWriteItemsInput.new(**opts).merge(
      transact_items: transact_items.map(&.item)
    )
    response = (client || dynamodb_client).transact_write_items(input)
    transact_items.each do |action|
      action.clean_after.try(&.clean!)
      action.destroy_after.try(&._data.destroyed=(true))
    end
    response
  end

  # Writes *record* the way `#save` would: a conditional put when it looks new, an update otherwise.
  #
  # Raises `Errors::TransactionalSaveConditionCollision` when a condition expression is given as
  # well, which cannot be combined with the generated existence check. Use `.put` instead and include
  # the check in your own condition expression.
  def self.save(record : Aws::Record::Base, **opts) : Aws::Record::TransactWriteAction
    return update(record, **opts) unless record.expect_new_item?
    if opts[:condition_expression]?
      raise Errors::TransactionalSaveConditionCollision.new(
        "Transactional write includes a :save operation that would result in a 'safe put' for the " \
        "given item, yet a condition expression was also provided. This is not currently supported. " \
        "You should rewrite this case to use a :put transaction, adding the existence check to your " \
        "own condition expression if desired.\n\tItem: #{record.to_h}\n\tExtra Options: #{opts}"
      )
    end
    condition, names = record.prevent_overwrite_expression
    put_action(
      Aws::DynamoDB::Types::Put.new(**opts).merge(
        condition_expression: condition, expression_attribute_names: names
      ),
      record
    )
  end

  # Writes *record*, overwriting whatever is in the table.
  def self.put(record : Aws::Record::Base, **opts) : Aws::Record::TransactWriteAction
    put_action(Aws::DynamoDB::Types::Put.new(**opts), record)
  end

  # Writes *record*'s changed attributes.
  def self.update(record : Aws::Record::Base, **opts) : Aws::Record::TransactWriteAction
    expression = record.class.build_update_expression(record.dirty_changes_for_update)
    update = expression.apply_to(Aws::DynamoDB::Types::Update.new(**opts)).merge(
      table_name: record.class.table_name, key: record.key_values
    )
    Aws::Record::TransactWriteAction.new(
      Aws::DynamoDB::Types::TransactWriteItem.new(update: update), clean_after: record
    )
  end

  # Deletes *record*.
  def self.delete(record : Aws::Record::Base, **opts) : Aws::Record::TransactWriteAction
    delete = Aws::DynamoDB::Types::Delete.new(**opts).merge(
      table_name: record.class.table_name, key: record.key_values
    )
    Aws::Record::TransactWriteAction.new(
      Aws::DynamoDB::Types::TransactWriteItem.new(delete: delete), destroy_after: record
    )
  end

  # Evaluates a condition without writing anything; build *check* with `Model.transact_check_expression`.
  def self.check(check : Aws::DynamoDB::Types::ConditionCheck) : Aws::Record::TransactWriteAction
    Aws::Record::TransactWriteAction.new(Aws::DynamoDB::Types::TransactWriteItem.new(condition_check: check))
  end

  private def self.put_action(put : Aws::DynamoDB::Types::Put,
                              record : Aws::Record::Base) : Aws::Record::TransactWriteAction
    Aws::Record::TransactWriteAction.new(
      Aws::DynamoDB::Types::TransactWriteItem.new(
        put: put.merge(table_name: record.class.table_name, item: record.save_values)
      ),
      clean_after: record
    )
  end

  private def self.build_find_result(requests, response) : Aws::Record::TransactFindResult
    responses = [] of Aws::Record::Base?
    missing = [] of Aws::Record::MissingItem
    (response.responses || [] of Aws::DynamoDB::Types::ItemResponse).each_with_index do |item_response, index|
      request = requests[index]
      item = item_response.item
      if item
        responses << request.model_class.build_item_from_resp(item)
      else
        responses << nil
        missing << Aws::Record::MissingItem.new(request.model_class, request.get.key || Aws::DynamoDB::Item.new)
      end
    end
    Aws::Record::TransactFindResult.new(responses, missing, response.consumed_capacity)
  end
end
