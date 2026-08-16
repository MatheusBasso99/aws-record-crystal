require "../dynamodb/paginator"
require "./base"

# The pages of a search, seen by `Aws::Record::ItemCollection` without its needing to know whether
# it is reading a query or a scan.
# :nodoc:
abstract class Aws::Record::SearchPages
  # Yields the items and pagination key of every page.
  abstract def each_page(& : Array(Aws::DynamoDB::Item), Aws::DynamoDB::Item? ->) : Nil
end

# The pages of one paginated client operation.
# :nodoc:
class Aws::Record::TypedSearchPages(I, O) < Aws::Record::SearchPages
  # Wraps *pages*.
  def initialize(@pages : Aws::DynamoDB::Pages(I, O)) : Nil
  end

  # :inherit:
  def each_page(& : Array(Aws::DynamoDB::Item), Aws::DynamoDB::Item? ->) : Nil
    @pages.each_page do |page|
      yield(page.items || [] of Aws::DynamoDB::Item, page.last_evaluated_key)
    end
  end
end

# The lazy result of a query or a scan.
#
# Iterating walks every page, fetching the next one only when it is needed, so `#first` costs a
# single request. Items are built into the model the search came from, or into whatever a
# `multi_model_filter` picks per item.
#
# ```
# Forum.query(key_condition_expression: "#H = :h", ...).each { |post| puts post.post_title }
# Forum.scan.first(10)
# ```
class Aws::Record::ItemCollection
  include Enumerable(Aws::Record::Base)

  # The pagination key of the most recently read page, or `nil` when there are no pages left.
  getter last_evaluated_key : Aws::DynamoDB::Item?

  # Creates a collection over *pages*, building items into *model*.
  def initialize(@pages : SearchPages, @model : Aws::Record::Base.class,
                 @model_filter : Proc(Aws::DynamoDB::Item, (Aws::Record::Base.class)?)? = nil) : Nil
  end

  # Yields every item of every page, fetching pages as it goes.
  def each(& : Aws::Record::Base ->) : Nil
    @pages.each_page do |items, key|
      @last_evaluated_key = key
      build_items(items).each { |record| yield record }
    end
  end

  # The items of the first page only.
  def page : Array(Aws::Record::Base)
    items = [] of Aws::Record::Base
    @pages.each_page do |raw_items, key|
      @last_evaluated_key = key
      items = build_items(raw_items)
      break
    end
    items
  end

  # Whether the search matched nothing at all.
  #
  # A page may be empty and still be followed by one that is not, so this reads on until it finds an
  # item or runs out of pages.
  def empty? : Bool
    @pages.each_page do |items, _|
      return false unless items.empty?
    end
    true
  end

  private def build_items(items) : Array(Aws::Record::Base)
    records = [] of Aws::Record::Base
    items.each do |item|
      filter = @model_filter
      model_class = filter ? filter.call(item) : @model
      next unless model_class
      records << model_class.build_item_from_resp(item)
    end
    records
  end
end
