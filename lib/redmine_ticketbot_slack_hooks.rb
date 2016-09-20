class RedmineTicketbotSlackHook < Redmine::Hook::Listener
  # def controller_issues_new_after_save(context={})
  #   debug=to_boolean(Setting.plugin_redmine_ticketbot['ticketbot_debug'])
  #   begin
  #     controller_issues_edit_after_save(context)
  #   rescue => error
  #     p error.inspect
  #   end
  # end
  def controller_issues_edit_after_save(context={})
    debug=to_boolean(Setting.plugin_redmine_ticketbot['ticketbot_debug'])
    begin
      ## Don't post error reporting stuff, since that is already on another channel
      unless Setting.plugin_redmine_ticketbot['ticketbot_redmine_ignore_user_ids'].split(",").include?(context[:journal].user.id.to_s)
        edit_username = "#{context[:journal].user.firstname} #{context[:journal].user.lastname}"
        unless context[:journal].user.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).count == 0 || context[:journal].user.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).first.value.nil? || context[:journal].user.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).first.value == ""
          edit_username = context[:journal].user.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).first.value
          if edit_username[0] != "@"
            edit_username = "@#{edit_username}"
          end
        end
        ## These are the users we want to CC (author, assignee, and watchers)
        cc_slack_usernames = []
        cc_redmine_users = [context[:issue].author, context[:issue].assigned_to]
        context[:issue].watchers.each do |watcher|
          cc_redmine_users << watcher.user
        end
        ##loop watchers and add them
        cc_redmine_users.uniq.each do |user|
          unless user.status == 3
            slack_username = "#{user.firstname} #{user.lastname}"
            unless user.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).count == 0 || user.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).first.value.nil? || user.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).first.value == ""
              slack_username = user.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).first.value
              if slack_username[0] != "@"
                slack_username = "@#{slack_username}"
              end
            end
            cc_slack_usernames << slack_username
          end
        end
        slack_text = "<#{Setting.where(name: 'protocol').first.value}://#{Setting.where(name: 'host_name').first.value}/issues/#{context[:issue].id}|#{context[:issue].id}> was updated by #{edit_username}."
        slack_channels = ['#redmine-activity']
        if context[:issue].status_id == 6
          slack_channels << "#redmine-returned"
        elsif context[:issue].status_id == 9
          slack_channels << "#redmine-peerreview"
        elsif context[:issue].status_id == 28
          slack_channels << "#redmine-funtesting"
        elsif context[:issue].status_id == 2
          slack_channels << "#redmine-inprogress"
        elsif context[:issue].status_id == 25
          slack_channels << "#redmine-pendingdeploy"
        elsif context[:issue].status_id == 33
          slack_channels << "#redmine-bareview"
        end
        slack_channels.each do |slack_channel|
          Curl.post(Setting.plugin_redmine_ticketbot['ticketbot_slack_webhook_url'], {:payload => {
            :pretext => slack_text,
            :username => Setting.plugin_redmine_ticketbot['ticketbot_slack_posting_username'],
            :icon_emoji => ':bar_chart:',
            :channel => slack_channel,
            :fields => [
                {
                  :title => "Subject",
                  :value => "<#{Setting.where(name: 'protocol').first.value}://#{Setting.where(name: 'host_name').first.value}/issues/#{context[:issue].id}|#{context[:issue].subject}>",
                },
                {
                  :title  => "CC",
                  :value => "#{cc_slack_usernames.uniq.join(', ')}",
                }
            ],
          }.to_json})
        end
      else
        if debug
          p "ignoring updates from user id: #{context[:journal].user.id.to_s}"
        end
      end
    rescue => error
      p 'something bad in slack hooks happened!'
      p error.inspect
    end
  end
  def to_boolean(str)
    str == 'true'
  end
end
