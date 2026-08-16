require "./base"

# Dirty tracking: which of an item's attributes have changed since it was last saved or loaded.
#
# The Ruby gem's `DirtyTracking` module; here these are instance methods of `Aws::Record::Base`,
# alongside the per-attribute `<name>_dirty?`, `<name>_dirty!`, `<name>_was` and
# `rollback_<name>!` methods the attribute macros generate.
class Aws::Record::Base
  # The names of the attributes that have changed.
  def dirty : Array(String)
    @data.dirty
  end

  # Whether any attribute has changed.
  def dirty? : Bool
    @data.dirty?
  end

  # Marks every attribute as unchanged, taking the current values as the clean ones.
  def clean! : Nil
    @data.clean!
  end

  # Whether this item has never been written to DynamoDB.
  def new_record? : Bool
    @data.new_record?
  end

  # Whether this item has been deleted from DynamoDB.
  def destroyed? : Bool
    @data.destroyed?
  end

  # Whether this item exists in DynamoDB as far as this instance knows.
  def persisted? : Bool
    @data.persisted?
  end

  # Whether *name* has changed since the item was last clean.
  def attribute_dirty?(name : String | Symbol) : Bool
    @data.attribute_dirty?(name)
  end

  # The value *name* had when the item was last clean.
  def attribute_was(name : String | Symbol) : Aws::Record::RawValue
    @data.attribute_was(name)
  end

  # Marks *name* as changed, whatever its value.
  def attribute_dirty!(name : String | Symbol) : Nil
    @data.attribute_dirty!(name)
  end

  # Restores *name* to the value it had when the item was last clean, and returns it.
  def rollback_attribute!(name : String | Symbol) : Aws::Record::RawValue
    @data.rollback_attribute!(name)
  end

  # Restores the named attributes — every changed one by default — to their clean values.
  #
  # ```
  # item.rollback!(:body)
  # item.rollback!
  # ```
  def rollback!(*names : String | Symbol) : Nil
    names.each { |name| rollback_attribute!(name) }
  end

  # :ditto:
  def rollback! : Nil
    dirty.each { |name| rollback_attribute!(name) }
  end
end
