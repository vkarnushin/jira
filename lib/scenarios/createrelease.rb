module Scenarios
  ##
  # CreateRelease scenario
  class CreateRelease
    def find_by_filter(issue, filter)
      issue.jql("filter=#{filter}", max_results: 100)
    rescue JIRA::HTTPError => jira_error
      error_message = jira_error.response['body_exists'] ? jira_error.message : jira_error.response.body
      LOGGER.error "Error in JIRA with the search by filter #{error_message}"
      []
    end

    def find_by_tasks(issue, tasks)
      issues_from_string = []

      tasks.split(',').each do |issue_key|
        # Try to find issue by key
        begin
          issues_from_string << issue.find(issue_key)
        rescue JIRA::HTTPError => jira_error
          error_message = jira_error.response['body_exists'] ? jira_error.message : jira_error.response.body

          LOGGER.error "Error in JIRA with the search by issue key #{error_message}"
        end
      end

      issues_from_string
    end

    def create_release_issue(project, issue, project_key = 'OTT', release_name = 'Release')
      project = project.find(project_key)
      release = issue.build
      release.save(fields: { summary: release_name, project: { id: project.id },
                             issuetype: { name: 'Release' } })
      release.fetch
      release
    rescue JIRA::HTTPError => jira_error
      error_message = jira_error.response['body_exists'] ? jira_error.message : jira_error.response.body
      LOGGER.error "Creation of release was failed with error #{error_message}"
      raise error_message
    end

    # :nocov:
    def run
      params = SimpleConfig.release

      unless params
        LOGGER.error 'No Release params in ENV'
        exit
      end

      if !params.filter && !params.tasks
        LOGGER.error 'No necessary params - filter of tasks'
        exit
      end

      LOGGER.info "Create release from filter #{params[:filter]} with name #{params[:name]}"

      client = JIRA::Client.new SimpleConfig.jira.to_h

      release_issues = []

      if params.filter
        LOGGER.info "Start search ticket from filter #{params.filter}"
        release_issues = params.filter && find_by_filter(client.Issue, params.filter)
        LOGGER.info "Filter #{params.filter} doesn't contains tickets" if release_issues.empty?
        LOGGER.info "Could find #{release_issues.size} tasks from filter #{params.filter}"
      end

      if params.tasks && !params.tasks.empty?
        LOGGER.info "Found tasks for release: #{params.tasks}. Start find them"
        tasks = find_by_tasks(client.Issue, params.tasks)
        LOGGER.info "Could find #{tasks.size} tasks. Add them to release ticket"
        release_issues += find_by_tasks(client.Issue, params.tasks)
      end

      if release_issues.empty?
        LOGGER.error 'Cant find any task for release ticket'
        Ott::Helpers.export_to_file("SLACK_URL=''", 'release_properties')
        exit(127)
      end

      begin
        release = create_release_issue(client.Project, client.Issue, params[:project], params[:name])
      rescue RuntimeError => e
        puts e.message
        puts e.backtrace.inspect
        raise
      end

      LOGGER.info "Start to link #{release_issues.size} issues to release #{release.key}"

      release_labels = []
      release_issues.each do |issue|
        issue.link(release.key)
        issue.related['branches'].each do |branch|
          release_labels << branch['repository']['name'].to_s
        end
      end

      release_labels.uniq!

      LOGGER.info "Created new release #{release.key} from filter #{params[:filter]}"

      LOGGER.info "Add labels: #{release_labels} to release #{release.key}"
      release_issue = client.Issue.find(release.key)
      release_issue.save(fields: { labels: release_labels })
      release_issue.fetch

      LOGGER.info "Storing '#{release.key}' to file, to refresh buildname in Jenkins"
      Ott::Helpers.export_to_file(release.key, 'release_name.txt')
      Ott::Helpers.export_to_file("export ISSUE=#{release.key}", 'set_env.sh')
      # For platform release through pipeline
      Ott::Helpers.export_to_file("env.ISSUE='#{release.key}'", 'pipeline_release_properties')
      # For other release through Jenkins build
      Ott::Helpers.export_to_file("SLACK_URL=#{SimpleConfig.jira.site}/browse/#{release.key}\n\r
                                        ISSUE=#{release.key}", 'release_properties')

    end

    # :nocov:
  end
end
