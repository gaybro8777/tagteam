# A HubFeed links a Hub with a Feed. A Hub has many HubFeeds.
#
# A HubFeed inherits most its metadata from its parent Feed, but a Hub owner can override the title and description by editing the HubFeed.
# 
# Most validations are contained in the ModelExtensions mixin.
#
class HubFeed < ActiveRecord::Base
  include ModelExtensions
  before_validation do
    auto_sanitize_html(:description)
  end
  include AuthUtilities

  acts_as_authorization_object
  acts_as_api do|c|
    c.allow_jsonp_callback = true
  end
  belongs_to :hub
  belongs_to :feed
  has_many :feed_items, :through => :feed
  has_many :hub_feed_tag_filters, :dependent => :destroy, :order => :position
  validates_uniqueness_of :feed_id, :scope => :hub_id
  validates_presence_of :feed_id, :hub_id

  scope :bookmark_collections, lambda { joins(:feed).where('feeds.bookmarking_feed' => true) }
  scope :rss, lambda { joins(:feed).where('feeds.bookmarking_feed' => false) }

  scope :need_updating, lambda { joins(:feed).where(['feeds.next_scheduled_retrieval <= ? and bookmarking_feed is false', Time.now]) }

  attr_accessible :title, :description

  api_accessible :default do|t|
    t.add :id
    t.add :display_title, :as => :title
    t.add :display_description, :as => :description
    t.add :link
    t.add :hub
    t.add :feed
  end
  
  after_create do
  #  logger.warn('After create is firing')
    reindex_items_of_concern
    Resque.enqueue(HubFeedFeedItemTagRenderer, self.id)
  end

  after_destroy do
    reindex_items_of_concern

    # Possibly not necessary, but I put this in for a reason at some point so it might be.
    ActsAsTaggableOn::Tagging.destroy_all(:context => self.hub.tagging_key.to_s, :taggable_type => 'FeedItem', :taggable_id => self.feed.feed_items.collect{|fi| fi.id})
    self.feed.feed_items.each do|fi|
      Resque.enqueue(FeedItemTagRenderer,fi.id)
    end
    Resque.enqueue(ReindexTags)
  end

  def hub_ids
    [self.hub_id]
  end

  searchable(:include => [:hub]) do
    text :display_title, :display_description, :link, :guid, :rights, :authors, :feed_url, :generator
    integer :hub_ids, :multiple => true

    integer :feed_item_ids, :multiple => true

    string :title
    string :guid
    time :last_updated
    string :rights
    string :authors
    string :feed_url
    string :link
    string :generator
    string :flavor
    string :language
  end

  def self.descriptive_name
    'Feed'
  end

  def display_title
    (self.title.blank?) ? self.feed.title : self.title
  end
  alias :to_s :display_title
  
  def display_description
    (self.description.blank?) ? self.feed.description : self.description
  end

  # Inherited from this HubFeed's feed.
  def link
    self.feed.link
  end

  # Inherited from this HubFeed's feed.
  def guid
    self.feed.guid
  end

  # Inherited from this HubFeed's feed.
  def rights
    self.feed.rights
  end

  # Inherited from this HubFeed's feed.
  def authors
    self.feed.authors
  end

  # Inherited from this HubFeed's feed.
  def feed_url
    self.feed.feed_url
  end
  
  # Inherited from this HubFeed's feed.
  def generator
    self.feed.generator
  end

  # Inherited from this HubFeed's feed.
  def last_updated
    self.feed.last_updated
  end

  # Inherited from this HubFeed's feed.
  def flavor
    self.feed.flavor
  end

  # Inherited from this HubFeed's feed.
  def language
    self.feed.language
  end

  def latest_successful_feed_retrieval
    feed.feed_retrievals.successful.last
  end

  def latest_feed_retrieval
    feed.feed_retrievals.last
  rescue Exception => e
    logger.warn(e.inspect)
    []
  end

  def latest_feed_items(limit = 15)
    self.feed.feed_items.limit(limit)
  rescue Exception => e
    logger.warn(e.inspect)
    []
  end

  # Around 15 (by default) of the latest tags. If tags appear more than once in the latest items, the limit will be off. This is a tradeoff for performance sake.
  def latest_tags(limit = 15)
    tags = ActsAsTaggableOn::Tagging.find(:all, :include => [:tag], :conditions => {:taggable_type => 'FeedItem', :taggable_id => self.latest_feed_items.collect{|fi| fi.id}, :context => self.hub.tagging_key.to_s}, :limit => limit).collect{|tg| tg.tag}.uniq
    return tags
  rescue Exception => e
    logger.warn(e.inspect)
    return []
  end

  private

  def reindex_items_of_concern
    logger.warn('reindexing everything')
    self.feed.solr_index
    self.feed.feed_items.collect{|fi| fi.solr_index}
  end

end
