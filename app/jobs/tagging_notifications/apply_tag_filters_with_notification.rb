# frozen_string_literal: true
module TaggingNotifications
  class ApplyTagFiltersWithNotification < ApplicationJob
    queue_as :default

    # This is a combined method because you can't async them, IE, you need to have apply tag filters
    # finish before send notification job starts to identify tag filter data
    def perform(feed_item, tag_filter, hub, updated_by_user)
      changes = []

      if feed_item.present?
        ::ApplyTagFilters.new.perform(hub.all_tag_filters.select { |tf| tf.scope_type != 'FeedItem' }.map(&:id), [feed_item.id], true)
        tag_name = tag_filter.type == 'ModifyTagFilter' ? tag_filter.new_tag.name : tag_filter.tag.name
        resulting_tag_filter = tag_filter.type == 'DeleteTagFilter' ? nil : TagFilter.find_recursive(hub.id, tag_name)

        if tag_filter.present?
          # In the case of a tag filter being applied and terminating in another filter,
          # the updater is sent a notification
          if ['AddTagFilter', 'ModifyTagFilter'].include?(tag_filter.type)
            if resulting_tag_filter.present?
              mod_changes = []
              if resulting_tag_filter.type == 'DeleteTagFilter'
                mod_changes << { type: :tags_deleted, values: [tag_name] }
              elsif resulting_tag_filter.type == 'ModifyTagFilter'
                mod_changes << { type: :tags_modified, values: [[tag_name], [resulting_tag_filter.new_tag.name]] }
              end
              SendNotificationJob.new.perform(hub, [feed_item], [], updated_by_user, mod_changes, :updater)
            end
          end

          changes =
            case "#{tag_filter.class.to_s}-#{resulting_tag_filter.class.to_s}"
            when 'DeleteTagFilter-NilClass'
              { type: :tags_deleted, values: [tag_filter.tag.name] }
            when 'ModifyTagFilter-DeleteTagFilter'
              { type: :tags_deleted, values: [tag_filter.tag.name] }
            when 'ModifyTagFilter-ModifyTagFilter'
              { type: :tags_modified, values: [[tag_filter.tag.name], [resulting_tag_filter.new_tag.name]] }
            when 'ModifyTagFilter-NilClass'
              { type: :tags_modified, values: [[tag_filter.tag.name], [tag_filter.new_tag.name]] }
            when 'AddTagFilter-ModifyTagFilter'
              { type: :tags_added, values: [resulting_tag_filter.new_tag.name] }
            end
          SendNotificationJob.new.perform(hub, [feed_item], [], updated_by_user, [changes], :owners)
        else
          # If this is a new feed item, send to owner/updater
          DeactivatedTagging.where(taggable_id: feed_item.id, deactivator_type: 'TagFilter', context: "hub_#{hub.id}").map(&:deactivator).uniq.each do |deactivator|
            if deactivator.is_a?(DeleteTagFilter)
              changes << { type: :tags_deleted, values: [deactivator.tag.name] }
            elsif deactivator.is_a?(ModifyTagFilter)
              changes << { type: :tags_modified, values: [[deactivator.tag.name], [deactivator.new_tag.name]] }
            end
          end
          SendNotificationJob.new.perform(hub, [feed_item], [], updated_by_user, changes.uniq, :updater)
        end
      elsif tag_filter.present?
        ::ApplyTagFilters.new.perform([tag_filter.id], [], false)
        changes =
          case tag_filter.class.to_s
          when 'DeleteTagFilter'
            { type: :tags_deleted, values: [tag_filter.tag.name] }
          when 'ModifyTagFilter'
            { type: :tags_modified, values: [[tag_filter.tag.name], [tag_filter.new_tag.name]] }
          when 'SupplementTagFilter'
            { type: :tags_supplemented, values: [[tag_filter.tag.name, tag_filter.new_tag.name]] }
          end
        SendNotificationJob.new.perform(hub, tag_filter.filtered_feed_items, [tag_filter], updated_by_user, [changes], :owners)
      end
    end
  end
end
