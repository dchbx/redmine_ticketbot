# ##this will merge code into stage and cause a deploy to preprod
#
# class RedmineTicketbotJenkinsHook < Redmine::Hook::Listener
#   def controller_issues_edit_after_save(context={})
#     debug=to_boolean(Setting.plugin_redmine_ticketbot['ticketbot_debug'])
#     if context[:issue].custom_values.where('custom_field_id = ?',Setting.plugin_redmine_ticketbot['ticketbot_github_pullrequest_link_custom_field_id'].to_i).count == 1
#       if context[:issue].status.id == Setting.plugin_redmine_ticketbot['ticketbot_jenkins_issue_status_id_to_deploy'].to_i
#         github_pr_link = context[:issue].custom_values.where('custom_field_id = ?',Setting.plugin_redmine_ticketbot['ticketbot_github_pullrequest_link_custom_field_id'].to_i).first.value
#         github_repo = Setting.plugin_redmine_ticketbot['ticketbot_github_repo']
#         octokit_client = Octokit::Client.new(:access_token => Setting.plugin_redmine_ticketbot['ticketbot_github_access_token'], :auto_paginate => true)
#         github_pr_num = github_pr_link.split("/").last.to_i
#         github_pr_info = octokit_client.pull_request(github_repo, github_pr_num)
#         github_pr_branch = github_pr_info.head.ref
#         begin
#           mergeInfo = octokit_client.merge(github_repo, Setting.plugin_redmine_ticketbot['ticketbot_jenkins_branch_for_deploy'], github_pr_branch)
#           p mergeInfo.inspect
#           thisIssue = Issue.where(id:context[:issue].id).first
#           thisIssue.status_id = Setting.plugin_redmine_ticketbot['ticketbot_jenkins_issue_status_id_after_deploy']
#           thisIssue.save
#         rescue => error
#           p error.inspect
#           p mergeInfo.inspect
#           thisIssue = Issue.where(id:context[:issue].id).first
#           thisIssue.status_id = Setting.plugin_redmine_ticketbot['ticketbot_jenkins_issue_status_id_to_deploy']
#           thisIssue.save
#         end
#       end
#     end
#   end
#   def to_boolean(str)
#     str == 'true'
#   end
# end
