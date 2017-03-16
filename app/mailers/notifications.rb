class Notifications < ActionMailer::Base
  default from: Tagteam::Application.config.default_sender

  def tag_change_notification(taggers, hub, old_tag, new_tag, updated_by)
    logger.info('Sending a notification about a tags change to ' + taggers.collect(&:email).join(','))

    @hub = hub
    @hub_url = hub_url(@hub)
    @old_tag = old_tag
    @new_tag = new_tag
    @updated_by = updated_by

    subject = 'Tag update in the ' + @hub.title + ' hub'
    mail(bcc: taggers.collect(&:email), subject: subject)
  end

  def item_change_notification(hub, modified_item, item_users, current_user)
    logger.info('Sending a notification about an items change to ' + item_users.collect(&:email).join(','))

    @hub = hub
    @hub_url = hub_url(@hub)
    @modified_item = modified_item
    @updated_by = current_user

    subject = 'Item update in the ' + @hub.title + ' hub'
    mail(bcc: item_users.collect(&:email), subject: subject)
  end
end
