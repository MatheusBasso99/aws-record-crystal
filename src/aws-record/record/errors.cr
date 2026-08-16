require "../dynamodb/errors"

# Errors raised by the record layer.
#
# `RecordError` and its subclasses relate to persisting items — both client errors and validation
# failures. The rest are configuration and modelling mistakes; the ones the Crystal port can catch
# at compile time are raised by the attribute macros instead, with the same wording.
module Aws::Record::Errors
  # Base class for errors relating to the persistence of items.
  class RecordError < Exception; end

  # Raised when a required key attribute is missing from an item when persistence is attempted.
  class KeyMissing < RecordError; end

  # Raised when you attempt to load a record from the database, but it does not exist there.
  class NotFound < RecordError; end

  # Raised when a conditional write fails.
  class ConditionalWriteFailed < RecordError
    # The underlying error, which may carry item data when the return values option was used.
    getter original_error : Aws::DynamoDB::Errors::ConditionalCheckFailedException

    # Creates the error, keeping the DynamoDB error that caused it.
    def initialize(message : String, @original_error : Aws::DynamoDB::Errors::ConditionalCheckFailedException) : Nil
      super(message)
    end
  end

  # Raised when a validation hook call to `#valid?` fails.
  class ValidationError < RecordError; end

  # Raised when an attribute is defined that has a name collision with an existing attribute.
  class NameCollision < Exception; end

  # Raised when you attempt to create an attribute whose name conflicts with a reserved name
  # (generally, an existing method name).
  #
  # Change the attribute name in the model; if the database uses that name, keep it with
  # `database_attribute_name`.
  class ReservedName < Exception; end

  # Raised when you attempt a table migration and your model class is invalid.
  class InvalidModel < Exception; end

  # Raised when you attempt update or delete operations on a table that does not exist.
  class TableDoesNotExist < Exception; end

  # Raised when a table configuration is missing settings it needs.
  class MissingRequiredConfiguration < Exception; end

  # Raised when your own condition expression would be combined with the auto-generated condition of
  # a "safe put" in a transactional write.
  #
  # Use a plain `:put` and include the key existence check in your own condition expression instead.
  class TransactionalSaveConditionCollision < Exception; end

  # Raised when your own update expression would be combined with the update expression generated
  # from an item's attribute changes.
  #
  # Perform the attribute updates yourself in your update expression instead.
  class UpdateExpressionCollision < Exception; end
end
