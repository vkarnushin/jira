module Scenarios
  ##
  # CreateRelease scenario
  class CreateRelease
    def run
      params = SimpleConfig.release
      puts "Create release from filter #{params[:filter]} with name #{params[:name]}".green

      client = JIRA::Client.new SimpleConfig.jira.to_h

      if !params.filter && !params.tasks
        puts "No necessary params - filter of tasks".red
      end

      if params.filter && !params.filter.empty?
        issues = client.Issue.jql("filter=#{params[:filter]}")
      end

      if params.tasks && !params.tasks.empty?
        issues_from_string = []

        params.tasks.split(',').each do |issue_key|
          # Try to find issue by key
          issues_from_string << client.Issue.find(issue_key)
        end

        issues = issues_from_string unless issues_from_string.empty?
      end

      project = client.Project.find(params[:project])
      release = client.Issue.build
      release.save('fields' => { 'summary' => params[:name], 'project' => { 'id' => project.id },
                                 'issuetype' => { 'name' => 'Release' } })
      release.fetch
      puts "Start to link issues to release #{release.key}".green

      issues.each { |issue| issue.link(release.key) }

      puts "Create new release #{release.key} from filter #{params[:filter]}".green
    end
  end
end
