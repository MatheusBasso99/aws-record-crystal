require "../src/aws-record-crystal"

class Post < Aws::Record::Base
  integer_attr :uuid, hash_key: true
  string_attr :name, range_key: true
  integer_attr :age
end

post = Post.find(uuid: 1, name: "Foo")
post.try(&.update(age: 1))

# Or, without reading the item first — this writes an update expression for `age` only:
Post.update(uuid: 1, name: "Foo", age: 1)
