Redmine::Plugin.register :redmine_ticketbot do
  name 'Redmine Ticketbot plugin'
  author 'IdeaCrew Inc'
  description 'This keeps the Pull Requests in GitHub up-to-date with their Redmine Issue.'
  version '0.0.1'
  url 'http://github.com/dchbx/redmine_ticketbot'
  author_url 'http://ideacrew.com'
  settings :default => {
    'ticketbot_debug'                                   =>  'false',
    'ticketbot_github_access_token'                     =>  '',
    'ticketbot_github_repo'                             =>  '',
    'ticketbot_github_pullrequest_link_custom_field_id' =>  '',
    'ticketbot_github_username_custom_field_id'         =>  '',
    'ticketbot_slack_posting_username'                  =>  'Redmine Bot',
    'ticketbot_slack_webhook_url'                       =>  '',
    'ticketbot_slack_username_custom_field_id'          =>  '',
  }, :partial => 'settings/ticketbot_settings'
end

require 'redmine_ticketbot_github_hooks'
require 'redmine_ticketbot_slack_hooks'
