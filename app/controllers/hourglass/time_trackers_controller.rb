# coding: utf-8
module Hourglass
  class TimeTrackersController < ApiBaseController
    accept_api_auth :index, :show, :start, :update, :bulk_update, :stop, :destroy, :bulk_destroy

    def index
      list_records Hourglass::TimeTracker
    end

    def show
      respond_with_success authorize get_time_tracker
    end

    def start
      time_tracker = authorize Hourglass::TimeTracker.new params[:time_tracker] ? time_tracker_params.except(:start) : {}
      if time_tracker.save
        post_to_slack(User.current, time_tracker.issue) if time_tracker.issue
        respond_with_success time_tracker
      else
        respond_with_error :bad_request, time_tracker.errors.full_messages, array_mode: :sentence
      end
    end

    def update
      do_update get_time_tracker, time_tracker_params
    end

    def bulk_update
      authorize Hourglass::TimeTracker
      bulk do |id, params|
        authorize_update time_tracker_from_id(id), time_tracker_params(params)
      end
    end

    def stop
      time_tracker = authorize get_time_tracker
      time_log, time_booking = time_tracker.transaction do
        time_log = time_tracker.stop
        authorize time_log, :booking_allowed? if time_log && time_tracker.project
        [time_log, time_log && time_log.time_booking]
      end
      if time_tracker.destroyed?
        respond_with_success({time_log: time_log, time_booking: time_booking}.compact)
      else
        error_messages = time_log.errors.full_messages
        error_messages += time_booking.errors.full_messages if time_booking
        respond_with_error :bad_request, error_messages, array_mode: :sentence
      end
    end

    def destroy
      authorize(get_time_tracker).destroy
      respond_with_success
    end

    def bulk_destroy
      authorize Hourglass::TimeTracker
      bulk do |id|
        authorize(time_tracker_from_id id).destroy
      end
    end

    private
    def time_tracker_params(params_hash = params.require(:time_tracker))
      params_hash.permit(:start, :comments, :round, :project_id, :issue_id, :activity_id, :user_id,
                         custom_field_values: custom_field_keys(params_hash))
    end

    def get_time_tracker
      params[:id] == 'current' ? current_time_tracker : time_tracker_from_id
    end

    def current_time_tracker
      User.current.hourglass_time_tracker or raise ActiveRecord::RecordNotFound
    end

    def time_tracker_from_id(id = params[:id])
      Hourglass::TimeTracker.find id
    end

    SLACK_CHANNEL = '#redmine'.freeze

    def post_to_slack(user, issue)
      params = {
        link_names: 1,
        username:   Setting.plugin_redmine_slack['username'],
        channel:    SLACK_CHANNEL,
        icon_url:   Setting.plugin_redmine_slack['icon'],
      }

      params[:text] = "[#{escape_for_slack(issue.project)}] #{escape_for_slack(issue.author)} started work on <#{object_url(issue)}|#{escape_for_slack(issue)}>#{mentions_for_slack(issue.description)}"

      attachment          = {}
      attachment[:text]   = escape_for_slack(issue.description) if issue.description
      attachment[:fields] = [
        {
          title: I18n.t("field_status"),
          value: escape_for_slack(issue.status.to_s),
          short: true
        },
        {
          title: I18n.t("field_priority"),
          value: escape_for_slack(issue.priority.to_s),
          short: true
        },
        {
          title: I18n.t("field_done_ratio"),
          value: escape_for_slack(issue.done_ratio.to_s),
          short: true
        },
        {
          title: I18n.t("field_assigned_to"),
          value: escape_for_slack(issue.assigned_to.to_s),
          short: true
        },
        {
          title: I18n.t("field_watcher"),
          value: escape_for_slack(issue.watcher_users.join(', ')),
          short: true
        }
      ]
      params[:attachments] = [attachment]

      begin
        client = HTTPClient.new
        client.ssl_config.cert_store.set_default_paths
        client.ssl_config.ssl_version = :auto
        client.post_async(Setting.plugin_redmine_slack['slack_url'], payload: params.to_json)

        update_issue_status(user, issue)
      rescue
        Rails.logger.error <<-ERROR
Failed to send notice to Slack for User#id:#{user.id} and Issue#id:#{issue.id}
#{ex.message}
#{ex.backtrace.join("\n")}
ERROR
      end
    end

    def escape_for_slack(text)
      text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    def mentions_for_slack(text)
      return nil if text.nil?

      names = extract_usernames_for_slack(text)
      names.present? ? "\nTo: " + names.join(', ') : nil
    end

    def extract_usernames_for_slack(text = '')
      if text.nil?
        text = ''
      end

      # slack usernames may only contain lowercase letters, numbers,
      # dashes and underscores and must start with a letter or number.
      text.scan(/@[a-z0-9][a-z0-9_\-]*/).uniq
    end

    def object_url(obj)
      if Setting.host_name.to_s =~ /\A(https?\:\/\/)?(.+?)(\:(\d+))?(\/.+)?\z/i
        host, port, prefix = $2, $4, $5

        Rails.application.routes.url_for(
          obj.event_url(host:        host,
                        protocol:    Setting.protocol,
                        port:        port,
                        script_name: prefix)
        )
      else
        Rails.application.routes.url_for(
          obj.event_url(host:     Setting.host_name,
                        protocol: Setting.protocol)
        )
      end
    end

=begin
    def update_working_on(user, issue)
      begin
        ::WorkingOnMailer.deliver_now(user, issue)
        update_issue_status(user, issue)
      rescue Exception => ex
        Rails.logger.error <<-ERROR
Failed to send notice to WorkingOn for User#id:#{user.id} and Issue#id:#{issue.id}
#{ex.message}
#{ex.backtrace.join("\n")}
ERROR
      end
    end
=end

    def update_issue_status(user, issue)
      new_status_id = case issue.status_id.to_i
                      when 1
                        # 新規 → 進行中
                        2
                      when 3
                        # 対応済み → テスト中
                        7
                      end
      return unless new_status_id

      new_status = IssueStatus.find_by_id(new_status_id)
      if issue.new_statuses_allowed_to(user).include?(new_status)
        issue.init_journal(user, 'ステータスを移行しました。')
        issue.status_id = new_status_id
        issue.save
      end
    end
  end
end
