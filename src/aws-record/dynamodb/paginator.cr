require "./types"

# Walks the pages of a paginated DynamoDB operation, re-issuing the request with the previous
# page's `last_evaluated_key` until the service stops returning one.
#
# `Client#query_pages` and `Client#scan_pages` return one of these; it is what
# `Aws::Record::ItemCollection` iterates, mirroring the Ruby SDK's `resp.each_page`.
class Aws::DynamoDB::Pages(I, O)
  # The input the first page was fetched with.
  getter input : I

  @first_page : O?

  # Creates a paginator that fetches pages by calling *fetch* with an input.
  def initialize(@input : I, @fetch : I -> O) : Nil
  end

  # The first page, fetched once and remembered.
  def first_page : O
    @first_page ||= @fetch.call(@input)
  end

  # Yields every page, starting with the first.
  def each_page(& : O ->) : Nil
    page = first_page
    loop do
      yield page
      key = page.last_evaluated_key
      break if key.nil? || key.empty?
      page = @fetch.call(@input.merge(exclusive_start_key: key))
    end
  end

  # Yields every item of every page.
  def each_item(& : Item ->) : Nil
    each_page do |page|
      page.items.try(&.each { |item| yield item })
    end
  end
end
