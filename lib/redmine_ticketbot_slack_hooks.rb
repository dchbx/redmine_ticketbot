class RedmineTicketbotGithubHook < Redmine::Hook::Listener
  def controller_issues_edit_after_save(context={})
    debug=to_boolean(Setting.plugin_redmine_ticketbot['ticketbot_debug'])
    p 'Coming from Slack hooks!'
    begin
      ## Don't post error reporting stuff, since that is already on another channel
      unless context[:journal].user.id == 177
        edit_username = "#{context[:journal].user.firstname} #{context[:journal].user.lastname}"
        assignee_username = "#{context[:issue].assigned_to.firstname} #{context[:issue].assigned_to.lastname}"
        author_username = "#{context[:issue].author.firstname} #{context[:issue].author.lastname}"
        unless context[:journal].user.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).count == 0 || context[:journal].user.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).first.value.nil? || context[:journal].user.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).first.value == ""
          edit_username = context[:journal].user.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).first.value
          if edit_username[0] != "@"
            edit_username = "@#{edit_username}"
          end
        end
        ## These are the users we want to CC (author, assignee, and watchers)
        cc_users = []
        unless context[:issue].assigned_to.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).count == 0 || context[:issue].assigned_to.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).first.value.nil? || context[:issue].assigned_to.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).first.value == ""
          assignee_username = context[:issue].assigned_to.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).first.value
          if assignee_username[0] != "@"
            assignee_username = "@#{assignee_username}"
          end
        end
        cc_users << assignee_username
        unless context[:issue].author.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).count == 0 || context[:issue].author.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).first.value.nil? || context[:issue].author.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).first.value == ""
          author_username = context[:journal].user.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).first.value
          if author_username[0] != "@"
            author_username = "@#{author_username}"
          end
        end
        cc_users << author_username
        ##loop watchers and add them
        context[:issue].watchers.each do |watcher|
          watcher_username = "#{watcher.user.firstname} #{watcher.user.lastname}"
          unless watcher.user.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).count == 0 || watcher.user.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).first.value.nil? || watcher.user.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).first.value == ""
            watcher_username = watcher.user.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_slack_username_custom_field_id'].to_i).first.value
            if watcher_username[0] != "@"
              watcher_username = "@#{watcher_username}"
            end
          end
          cc_users << watcher_username
        end
        slack_text = "<#{Setting.where(name: 'protocol').first.value}://#{Setting.where(name: 'host_name').first.value}/issues/#{context[:issue].id}|#{context[:issue].id}> was updated by #{edit_username}.\n    CC #{cc_users.join(', ')}"
        slack_channels = ['#redmine-activity']
        slack_channels.each do |slack_channel|
          Curl.post(Setting.plugin_redmine_ticketbot['ticketbot_slack_webhook_url'], {:payload => {
            :text => slack_text,
            :username => Setting.plugin_redmine_ticketbot['ticketbot_slack_posting_username'],
            :icon_emoji => ':bar_chart:',
            :channel => slack_channel
          }.to_json})
        end
      end
    rescue
      p 'something bad in slack hooks happened!'
    end
  end
  def to_boolean(str)
    str == 'true'
  end
end
