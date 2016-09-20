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
    # require 'helper'
    # helper :journals
    debug=to_boolean(Setting.plugin_redmine_ticketbot['ticketbot_debug'])
    begin
      ## Don't post error reporting stuff, since that is already on another channel
      unless Setting.plugin_redmine_ticketbot['ticketbot_redmine_ignore_user_ids'].split(",").include?(context[:journal].user.id.to_s) && context[:journal].details.count > 0
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
        ##start building out the Slack call variables
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
        redmine_updates_string = "- #{details_to_strings(context[:journal].details,true).join("\n- ")}"
        unless context[:journal].notes == ""
          redmine_updates_string = "#{redmine_updates_string}\n- Note added: #{context[:journal].notes}"
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
                  :title => "Updates",
                  :value => redmine_updates_string
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
  ##### STOLE FROM issues_helper.rb #####
  # Returns the textual representation of a journal details
  # as an array of strings
  def details_to_strings(details, no_html=false, options={})
    options[:only_path] = (options[:only_path] == false ? false : true)
    strings = []
    values_by_field = {}
    details.each do |detail|
      if detail.property == 'cf'
        field = detail.custom_field
        if field && field.multiple?
          values_by_field[field] ||= {:added => [], :deleted => []}
          if detail.old_value
            values_by_field[field][:deleted] << detail.old_value
          end
          if detail.value
            values_by_field[field][:added] << detail.value
          end
          next
        end
      end
      strings << show_detail(detail, no_html, options)
    end
    if values_by_field.present?
      multiple_values_detail = Struct.new(:property, :prop_key, :custom_field, :old_value, :value)
      values_by_field.each do |field, changes|
        if changes[:added].any?
          detail = multiple_values_detail.new('cf', field.id.to_s, field)
          detail.value = changes[:added]
          strings << show_detail(detail, no_html, options)
        end
        if changes[:deleted].any?
          detail = multiple_values_detail.new('cf', field.id.to_s, field)
          detail.old_value = changes[:deleted]
          strings << show_detail(detail, no_html, options)
        end
      end
    end
    strings
  end
  # Returns the textual representation of a single journal detail
  def show_detail(detail, no_html=false, options={})
    multiple = false
    show_diff = false

    case detail.property
    when 'attr'
      field = detail.prop_key.to_s.gsub(/\_id$/, "")
      label = l(("field_" + field).to_sym)
      case detail.prop_key
      when 'due_date', 'start_date'
        value = format_date(detail.value.to_date) if detail.value
        old_value = format_date(detail.old_value.to_date) if detail.old_value

      when 'project_id', 'status_id', 'tracker_id', 'assigned_to_id',
            'priority_id', 'category_id', 'fixed_version_id'
        value = find_name_by_reflection(field, detail.value)
        old_value = find_name_by_reflection(field, detail.old_value)

      when 'estimated_hours'
        value = "%0.02f" % detail.value.to_f unless detail.value.blank?
        old_value = "%0.02f" % detail.old_value.to_f unless detail.old_value.blank?

      when 'parent_id'
        label = l(:field_parent_issue)
        value = "##{detail.value}" unless detail.value.blank?
        old_value = "##{detail.old_value}" unless detail.old_value.blank?

      when 'is_private'
        value = l(detail.value == "0" ? :general_text_No : :general_text_Yes) unless detail.value.blank?
        old_value = l(detail.old_value == "0" ? :general_text_No : :general_text_Yes) unless detail.old_value.blank?

      when 'description'
        show_diff = true
      end
    when 'cf'
      custom_field = detail.custom_field
      if custom_field
        label = custom_field.name
        if custom_field.format.class.change_as_diff
          show_diff = true
        else
          multiple = custom_field.multiple?
          value = detail.value if detail.value
          old_value = detail.old_value if detail.old_value
        end
      end
    when 'attachment'
      label = l(:label_attachment)
    when 'relation'
      if detail.value && !detail.old_value
        rel_issue = Issue.visible.find_by_id(detail.value)
        value = rel_issue.nil? ? "#{l(:label_issue)} ##{detail.value}" :
                  (no_html ? rel_issue : link_to_issue(rel_issue, :only_path => options[:only_path]))
      elsif detail.old_value && !detail.value
        rel_issue = Issue.visible.find_by_id(detail.old_value)
        old_value = rel_issue.nil? ? "#{l(:label_issue)} ##{detail.old_value}" :
                          (no_html ? rel_issue : link_to_issue(rel_issue, :only_path => options[:only_path]))
      end
      relation_type = IssueRelation::TYPES[detail.prop_key]
      label = l(relation_type[:name]) if relation_type
    end
    #call_hook(:helper_issues_show_detail_after_setting,
    #          {:detail => detail, :label => label, :value => value, :old_value => old_value })

    label ||= detail.prop_key
    value ||= detail.value
    old_value ||= detail.old_value

    unless no_html
      label = content_tag('strong', label)
      old_value = content_tag("i", h(old_value)) if detail.old_value
      if detail.old_value && detail.value.blank? && detail.property != 'relation'
        old_value = content_tag("del", old_value)
      end
      if detail.property == 'attachment' && value.present? &&
          atta = detail.journal.journalized.attachments.detect {|a| a.id == detail.prop_key.to_i}
        # Link to the attachment if it has not been removed
        value = link_to_attachment(atta, :download => true, :only_path => options[:only_path])
        if options[:only_path] != false && atta.is_text?
          value += link_to(
                       image_tag('magnifier.png'),
                       :controller => 'attachments', :action => 'show',
                       :id => atta, :filename => atta.filename
                     )
        end
      else
        value = content_tag("i", h(value)) if value
      end
    end

    if show_diff
      s = l(:text_journal_changed_no_detail, :label => label)
      unless no_html
        diff_link = link_to 'diff',
          {:controller => 'journals', :action => 'diff', :id => detail.journal_id,
           :detail_id => detail.id, :only_path => options[:only_path]},
          :title => l(:label_view_diff)
        s << " (#{ diff_link })"
      end
      s.html_safe
    elsif detail.value.present?
      case detail.property
      when 'attr', 'cf'
        if detail.old_value.present?
          l(:text_journal_changed, :label => label, :old => old_value, :new => value).html_safe
        elsif multiple
          l(:text_journal_added, :label => label, :value => value).html_safe
        else
          l(:text_journal_set_to, :label => label, :value => value).html_safe
        end
      when 'attachment', 'relation'
        l(:text_journal_added, :label => label, :value => value).html_safe
      end
    else
      l(:text_journal_deleted, :label => label, :old => old_value).html_safe
    end
  end
  # Find the name of an associated record stored in the field attribute
  def find_name_by_reflection(field, id)
    unless id.present?
      return nil
    end
    @detail_value_name_by_reflection ||= Hash.new do |hash, key|
      association = Issue.reflect_on_association(key.first.to_sym)
      name = nil
      if association
        record = association.klass.find_by_id(key.last)
        if record
          name = record.name.force_encoding('UTF-8')
        end
      end
      hash[key] = name
    end
    @detail_value_name_by_reflection[[field, id]]
  end

end
