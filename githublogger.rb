=begin
Plugin: Github Logger
Description: Logs daily Github activity (public and private) for the specified user.
Author: [David Barry](https://github.com/DavidBarry) 
Configuration:
  github_user: githubuser
  github_token: githubtoken
  github_tags: "#social #coding"
Notes:
This requires getting an OAuth token from GitHub to get access to your private commit activity.
You can get a token by running this command in the terminal:
curl -u 'username' -d '{"scopes":["repo"],"note":"Help example"}' https://api.github.com/authorizations
where username is your github username.
=end
# NOTE: Requires json gem
config = {
  'description' => ['Logs daily Github activity (public and private) for the specified user.',
                    'github_user should be your Github username',
                    'Instructions to get Github token <https://help.github.com/articles/creating-an-oauth-token-for-command-line-use>'],
  'github_user' => '',
  'github_token' => '',
  'github_tags' => '#development',
}
$slog.register_plugin({ 'class' => 'GithubLogger', 'config' => config })

class GithubLogger < Slogger

  def do_log
    if @config.key?(self.class.name)
        config = @config[self.class.name]
        if !config.key?('github_user') || config['github_user'] == ''
          @log.warn("GitHub user has not been configured or is invalid, please edit your slogger_config file.")
          return
        end

        if !config.key?('github_token') || config['github_token'] == ''
          @log.warn("GitHub token has not been configured, please edit your slogger_config file.")
          return
        end
    else
      @log.warn("GitHub Logger has not been configured, please edit your slogger_config file.")
      return
    end
    @log.info("Logging GitHub activity for #{config['github_user']}")
    begin
      url = URI.parse "https://api.github.com/users/#{config['github_user']}/events?access_token=#{config['github_token']}"

      res = Net::HTTP.start(url.host, use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http|
        http.get url.request_uri, 'User-Agent' => 'Slogger'
      end

    rescue Exception => e
      @log.error("ERROR retrieving GitHub url: #{url}")
    end

    return false if res.nil?
    json = JSON.parse(res.body)

    output = ""

    # json.each { |action|
    #   date = Time.parse(action['created_at'])
    #   if date > @timespan
    #     case action['type']
    #       when "PushEvent"
    #         if !action['repo']
    #           action['repo'] = {"name" => "unknown repository"}
    #         end
    #         output += "* Pushed to branch *#{action['payload']['ref'].gsub(/refs\/heads\//,'')}* of [#{action['repo']['name']}](#{action['url']})\n"
    #         action['payload']['commits'].each do |commit|
    #           output += "    * #{commit['message'].gsub(/\n+/," ")}\n" 
    #         end
    #     end
    #   else
    #     break
    #   end
    # }

    json.each { |action|
      case action['type']
      when 'PullRequestEvent'
        if action['payload']['action'] == 'opened'
          output += "Opened pull request [##{action['payload']['number']}](#{action['payload']['pull_request']['html_url']}): #{action['payload']['pull_request']['title']}\n"
        else
          output += "Closed pull request [##{action['payload']['number']}](#{action['payload']['pull_request']['html_url']}): #{action['payload']['pull_request']['title']}\n"
        end
      when 'WatchEvent'
        output += "&#9733; [#{action['repo']['name']}](https://github.com/#{action['repo']['name']})\n"
      when 'IssuesEvent'
        if action['payload']['action'] == 'closed'
          output += "&#10004; #{action['payload']['issue']['title']}\n"
        else
          output += "&#10007; #{action['payload']['issue']['title']}\n"
        end
      when 'PushEvent'
        if !action['repo']
          action['repo'] = {"name" => "unknown repository"}
        end
        output += "Pushed [#{action['payload']['commits'].count} commits](https://github.com/#{action['repo']['name']}/compare/#{action['payload']['before']}...#{action['payload']['head']}) to *#{action['payload']['ref'].gsub(/refs\/heads\//,'')}* of #{action['repo']['name']}\n"
        # action['payload']['commits'].each do |commit|
        #   output += "    * #{commit['message'].gsub(/\n+/," ")}\n" 
        # end
      end
    }

    return false if output.strip == ""
    entry = "GitHub activity for #{Time.now.strftime(@date_format)}:\n\n#{output}\n#{config['github_tags']}"
    puts entry
    DayOne.new.to_dayone({ 'content' => entry })
  end

end
