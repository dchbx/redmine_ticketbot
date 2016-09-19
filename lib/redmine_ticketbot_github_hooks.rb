class RedmineTicketbotHook < Redmine::Hook::Listener
  def controller_issues_edit_after_save(context={})
    debug=to_boolean(Setting.plugin_redmine_ticketbot['ticketbot_debug'])
    unless context[:issue].custom_values.where('custom_field_id = ?',Setting.plugin_redmine_ticketbot['ticketbot_github_pullrequest_link_custom_field_id'].to_i).count == 0
      github_pr_link = context[:issue].custom_values.where('custom_field_id = ?',Setting.plugin_redmine_ticketbot['ticketbot_github_pullrequest_link_custom_field_id'].to_i).first.value
      github_repo = Setting.plugin_redmine_ticketbot['ticketbot_github_repo']
      octokit_client = Octokit::Client.new(:access_token => Setting.plugin_redmine_ticketbot['ticketbot_github_access_token'], :auto_paginate => true)
      if debug
        p "1: #{github_pr_link.inspect}"
      end
      if github_pr_link.nil? || github_pr_link == ""
        if debug
          p "2: #{github_pr_link.inspect}"
        end
        ##try to find a branch that contains the Redmine issue # and open a PR for it
        #Then add that PR number to the redmine ticket, and sync them up!
        new_github_pr_link = false
        all_branches = octokit_client.branches(github_repo)
        all_branches.each do |branch|
          if branch.name.include? context[:issue].id.to_s
            all_open_prs = octokit_client.pull_requests(github_repo)
            if debug
              p "3: #{branch_name.inspect}"
            end
            all_open_prs.each do |pr|
              ##link to a current pull request
              if pr.head.ref == branch.name
                if debug
                  p "3.1: #{pr.inspect}"
                end
                new_github_pr_link = pr.html_url
                break
              end
            end
            unless new_github_pr_link
              ##create the pull request
              new_pr = octokit_client.create_pull_request(github_repo,'master',branch.name,context[:issue].subject,"https://devops.dchbx.org/redmine/issues/#{context[:issue].id}")
              if debug
                p "4: #{new_pr.inspect}"
              end
              new_github_pr_link = new_pr.html_url
            end
            ##save new github PR link
            pr_field = context[:issue].custom_values.where('custom_field_id = ?',Setting.plugin_redmine_ticketbot['ticketbot_github_pullrequest_link_custom_field_id'].to_i).first
            pr_field.value = new_github_pr_link
            pr_field.save
            break
          end
        end
      end
      unless github_pr_link.nil? || github_pr_link == ""
        if debug
          p "5: #{github_pr_link.inspect}"
        end
        ## Figure out PR number
        github_pr_num = github_pr_link.split("/").last.to_i
        ## Apply labels to our PR
        begin
          labels = [
            "Status: #{context[:issue].status.name}",
            "Tracker: #{context[:issue].tracker.name}",
            "Priority: #{context[:issue].priority.name}"
          ]
          if debug
            p "6: #{labels.inspect}"
          end
          ## Add assignee
          if context[:issue].assigned_to.nil?
            labels << "Assignee: NOT ASSIGNED"
            ##FIXME:  make sure assignee is removed from pr
            octokit_client.update_issue(github_repo, github_pr_num, :assignees => [])
          else
            if context[:issue].assigned_to.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_github_username_custom_field_id'].to_i).count == 0 || context[:issue].assigned_to.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_github_username_custom_field_id'].to_i).first.value.nil? || context[:issue].assigned_to.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_github_username_custom_field_id'].to_i).first.value == ""
              labels << "Assignee: #{context[:issue].assigned_to.firstname} #{context[:issue].assigned_to.lastname}"
              ##FIXME:  make sure assignee is removed from pr
              add_assignee_pr_update = octokit_client.update_issue(github_repo, github_pr_num, :assignees => [])
              if debug
                p "6.1: #{add_assignee_pr_update}"
              end
            else
              octokit_client.update_issue(github_repo, github_pr_num, :assignees => [context[:issue].assigned_to.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_github_username_custom_field_id'].to_i).first.value])
            end
          end
          if debug
            p "7: #{labels.inspect}"
          end
          ##figure out labels for the PRs
          current_repo_labels = octokit_client.labels(github_repo)
          labels.each do |label|
            labelExists = false
            current_repo_labels.each do |currentLabel|
              if currentLabel.name.to_s == label.to_s
                labelExists = true
              end
            end
            if labelExists == false
              octokit_client.add_label(github_repo, label, 'ffffff')
            end
          end
          ## delete any labels that we need to remove for this PR
          current_pr_labels = octokit_client.labels_for_issue(github_repo, github_pr_num)
          current_pr_labels.each do |currentLabel|
            labelExists = false
            labels.each do |label|
              if currentLabel.name == label
                labelExists = true
              end
            end
            if labelExists == false
              octokit_client.remove_label(github_repo, github_pr_num, currentLabel.name)
            end
          end
          ## add all the labels needed
          labels.each do |label|
            labelExists = false
            current_pr_labels.each do |currentLabel|
              if currentLabel.name == label
                labelExists = true
              end
            end
            if labelExists == false
              octokit_client.add_labels_to_an_issue(github_repo, github_pr_num, [label])
            end
          end
          if debug
            p "8: labels all updated"
          end
        rescue
          if debug
            p "9: Debug Point"
          end
        end
        ## Apply the milestone to our PR
        redmine_version_id_to_github_milestone_id = {
          103 => "1",
          104 => "2",
          106 => "3",
          107 => "4"
        }
        unless redmine_version_id_to_github_milestone_id[context[:issue].fixed_version_id].nil?
          if debug
            p "10: #{redmine_version_id_to_github_milestone_id[context[:issue].fixed_version_id].inspect}"
          end
          octokit_client.update_issue(github_repo, github_pr_num, :milestone => redmine_version_id_to_github_milestone_id[context[:issue].fixed_version_id])
        end
        ## Figure out what the state of the PR should be
        state = "closed"
        unless context[:issue].status.is_closed
          state = "open"
        end
        if debug
          p "11: #{state.inspect}"
        end
        ## FIXME: this will error if the PR is already merged and we try to re-open it.
        ##uniform the output of the Pull Request body
        if context[:issue].author.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_github_username_custom_field_id'].to_i).count == 0 || context[:issue].author.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_github_username_custom_field_id'].to_i).first.value.nil? || context[:issue].author.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_github_username_custom_field_id'].to_i).first.value == ""
          ticket_author = "#{context[:issue].author.firstname} #{context[:issue].author.lastname}"
        else
          ticket_author = "@#{context[:issue].author.custom_values.where(custom_field_id: Setting.plugin_redmine_ticketbot['ticketbot_github_username_custom_field_id'].to_i).first.value}"
        end
        if context[:issue].custom_values.where(custom_field_id: 22).count == 0 || context[:issue].custom_values.where(custom_field_id: 22).first.value.nil? || context[:issue].custom_values.where(custom_field_id: 22).first.value == ""
          wbs_num = "n/a"
        else
          wbs_num = context[:issue].custom_values.where(custom_field_id: 22).first.value
        end
        if context[:issue].custom_values.where(custom_field_id: 28).count == 0 || context[:issue].custom_values.where(custom_field_id: 28).first.value.nil? || context[:issue].custom_values.where(custom_field_id: 28).first.value == ""
          dev_priority = "n/a"
        else
          dev_priority = context[:issue].custom_values.where(custom_field_id: 28).first.value
        end
        if context[:issue].custom_values.where(custom_field_id: 24).count == 0 || context[:issue].custom_values.where(custom_field_id: 24).first.value.nil? || context[:issue].custom_values.where(custom_field_id: 24).first.value == ""
          dev_story_points = "n/a"
        else
          dev_story_points = context[:issue].custom_values.where(custom_field_id: 24).first.value
        end
        if context[:issue].custom_values.where(custom_field_id: 29).count == 0 || context[:issue].custom_values.where(custom_field_id: 29).first.value.nil? || context[:issue].custom_values.where(custom_field_id: 29).first.value == ""
          peer_story_points = "n/a"
        else
          peer_story_points = context[:issue].custom_values.where(custom_field_id: 29).first.value
        end
        if context[:issue].due_date.nil? || context[:issue].due_date == ""
          due_date = "n/a";
        else
          due_date = context[:issue].due_date.strftime("%m/%d/%Y")
        end
        if context[:issue].start_date.nil? || context[:issue].start_date == ""
          start_date = "n/a";
        else
          start_date = context[:issue].start_date.strftime("%m/%d/%Y")
        end
        if debug
          p "12: #{ticket_author}"
        end
        pr_body="|Field|Value|
|-----|-----|
| Redmine Ticket Number | [#{context[:issue].id}](https://devops.dchbx.org/redmine/issues/#{context[:issue].id}) |
| App-Dev Road Map # | #{wbs_num} |
| Start Date | #{start_date} |
| Due Date | #{due_date}  |
| App-Dev Priority | #{dev_priority} |
| Development Story Points | #{dev_story_points} |
| Peer Review Story Points | #{peer_story_points} |
| Ticket Author | #{ticket_author} |"
        if debug
          p "13.1: #{github_repo}"
          p "13.2: #{github_pr_num}"
          p "13.3: #{context[:issue].subject}"
          p "13.4: #{pr_body.inspect}"
          p "13.5: #{state.inspect}"
        end
        begin
          update_pr = octokit_client.update_pull_request(github_repo,github_pr_num,:title => "#{context[:issue].id}: #{context[:issue].subject}",:body => pr_body,:state => state)
        rescue => error
          p error.inspect
        end
        if debug
          p "14: #{update_pr.inspect}"
        end
      end
    end
  end
  def to_boolean(str)
    str == 'true'
  end
end
