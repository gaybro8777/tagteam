class Feed < ActiveRecord::Base
  include FeedUtilities
  include AuthUtilities
  acts_as_authorization_object

	attr_accessible :feed_url
	attr_accessor :raw_feed
	has_and_belongs_to_many :hub_feeds
  has_many :feed_retrievals
  has_many :feed_items

  validates_presence_of :feed_url

	before_validation do
		return false if feed_url.blank?
		if ! feed_url.match(/https?:\/\/.+/i).nil?
			rss_feed = test_single_feed(self)
      return false unless rss_feed
		else
			return false
		end
	end

end