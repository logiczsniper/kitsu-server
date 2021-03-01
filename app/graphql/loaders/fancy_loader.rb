# +FancyLoader+ allows for easily batching complex custom sorts and pagination. It does so through
# heavy use of complex Arel and Postgres window functions, but has performance attributes that make
# it worthwhile.
#
# To use +FancyLoader+, you'll make a subclass to define your sorts and source model. You can then
# create a field which uses your subclass to load data.

class Loaders::FancyLoader < GraphQL::Batch::Loader
  include Loaders::FancyLoader::DSL

  # Get an autogenerated GraphQL type for an order input
  def self.sort_argument
    @sort_argument ||= Loaders::FancyLoader::TypeGenerator.new(self).sorts_list
  end

  # Override the loader key to handle arbitrarily-nested arguments.
  #
  # @todo There *must* be a better way to handle this
  def self.loader_key_for(*group_args, **group_kwargs)
    [group_args, Oj.dump(group_kwargs)]
  end

  # Get a FancyConnection wrapping this Loader
  def self.connection_for(args, key)
    Connections::FancyConnection.new(self, args, key)
  end

  # Initialize a FancyLoader. This takes all the keys which are used to batch, which is a *lot* of
  # them. Thanks to the design of GraphQL, however, the frequently-called fields also tend to have
  # the same parameters each time. This means that we can get away with this less-than-ideal
  # batching and still have significant performance gains.
  #
  # The pagination parameters have some odd interactions to be aware of! They are *intersected*, so
  # if you pass before and after, you're specifying after < row < before. That's pretty logical,
  # but first+last are weirder, because when combined they will return the *middle*, due to that
  # intersection-driven logic. That is, given a set of 10 rows, first=6 & last=6 will return rows
  # 4, 5, and 6 because they are the only ones in both sets. This isn't a particularly useful
  # behavior, but the Relay spec is pretty clear that you shouldn't expect good results if you pass
  # both first and last to the same field.
  #
  # @param find_by [Symbol, String] the key to find by
  # @param before [Integer] Filter by rows less than this
  # @param after [Integer] Filter by rows greater than this
  # @param first [Integer] Filter for first N rows
  # @param last [Integer] Filter for last N rows
  # @param sort [Array<{:on, :direction => Symbol}>] The sorts to apply while loading
  # @param token [Doorkeeper::AccessToken] the user's access token
  def initialize(find_by:, sort:, token:, before: nil, after: 0, first: nil, last: nil, where: nil)
    @find_by = find_by
    @sort = sort.map(&:to_h)
    @token = token
    @before = before
    @after = after
    @first = first
    @last = last
    @where = where
  end

  # Perform the loading. Uses {Loaders::FancyLoader::QueryGenerator} to build a query, then groups
  # the results by the @find_by column, then fulfills all the Promises.
  def perform(keys)
    query = QueryGenerator.new(
      model: model,
      find_by: @find_by,
      before: @before,
      after: @after,
      first: @first,
      last: @last,
      sort: sort,
      token: @token,
      keys: keys,
      where: @where
    ).query

    results = query.to_a.group_by { |rec| rec[@find_by] }
    keys.each do |key|
      fulfill(key, results[key] || [])
    end
  end

  private

  def sort
    @sort.map do |sort|
      sorts[sort[:on]].merge(direction: sort[:direction])
    end
  end
end
