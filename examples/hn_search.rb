# HNSearch
# API access for news.ycombinator.com
module HNSearch
  class Base < WellRested::Base
    self.server = 'api.thriftdb.com/api.hnsearch.com'
  end

  class User < Base
    self.path = '/users'

    def items(api)
      Item.search_items_by_username(api, self.username)
    end
  end

  class Item < Base
    self.path = '/items'

    def self.search_items_by_username(api, username)
      api.get("#{protocol}://#{server}/items/_search", :filter => { :fields => { :username => username } })
    end
  end

  def self.your_author(api)
    api.find(User, :id => 'nick_urban')
  end
end


