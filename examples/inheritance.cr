require "../src/aws-record-crystal"

class Animal < Aws::Record::Base
  string_attr :name, hash_key: true
  integer_attr :age
end

class Dog < Animal
  boolean_attr :family_friendly
end

if dog = Dog.find(name: "Sunflower")
  dog.age = 3
  dog.family_friendly = true
  dog.save!
end
