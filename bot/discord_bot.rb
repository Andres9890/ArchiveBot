require 'discordrb'
require 'redis'
require 'trollop'
require 'uri'

require File.expand_path('../brain', __FILE__)
require File.expand_path('../discord_adapters', __FILE__)
require File.expand_path('../../lib/couchdb', __FILE__)

opts = Trollop.options do
  opt :token, 'Discord bot token', type: String
  opt :client_id, 'Discord application client ID', type: String
  opt :guilds, 'Comma-separated list of guild IDs to register commands in', type: String
  opt :schemes, 'Comma-separated list of acceptable URI schemes', default: 'http,https,ftp'
  opt :redis, 'URL of Redis server', default: ENV['REDIS_URL'] || 'redis://localhost:6379/0'
  opt :db, 'URL of CouchDB database', default: ENV['COUCHDB_URL'] || 'http://localhost:5984/archivebot'
  opt :db_credentials, 'Credentials for CouchDB database (USERNAME:PASSWORD)', type: String, default: nil
end

%i[token client_id].each do |key|
  Trollop.die("--#{key} is required") unless opts[key]
end

schemes = opts[:schemes].split(',').map(&:strip)
guild_ids = (opts[:guilds] || '').split(',').map(&:strip).reject(&:empty?).map(&:to_i)
client_id = opts[:client_id].to_i

redis = Redis.new(url: opts[:redis])
couchdb = Couchdb.new(URI(opts[:db]), opts[:db_credentials])
brain = Brain.new(schemes, redis, couchdb)

bot = Discordrb::Bot.new(
  token: opts[:token],
  client_id: client_id,
  intents: %i[server_messages direct_messages server_members]
)

module DiscordCommandHelpers
  module_function

  def register_command(bot, name, description, guild_ids, &block)
    if guild_ids.empty?
      bot.register_application_command(name, description, &block)
    else
      guild_ids.each do |guild_id|
        bot.register_application_command(name, description, guild_id: guild_id, &block)
      end
    end
  end

  def option(event, key)
    event.options[key.to_s] || event.options[key.to_sym]
  end
end

DiscordCommandHelpers.register_command(bot, :archive, 'Queue a URL for archival', guild_ids) do |cmd|
  cmd.string('url', 'URL to archive', required: true)
  cmd.string('parameters', 'Optional job parameters', required: false)
end

DiscordCommandHelpers.register_command(bot, :archive_file, 'Queue URLs from a file for archival', guild_ids) do |cmd|
  cmd.string('url', 'URL pointing to the list of URLs', required: true)
  cmd.string('parameters', 'Optional job parameters', required: false)
end

DiscordCommandHelpers.register_command(bot, :archiveonly, 'Queue a URL without recursion', guild_ids) do |cmd|
  cmd.string('url', 'URL to archive without recursion', required: true)
  cmd.string('parameters', 'Optional job parameters', required: false)
end

DiscordCommandHelpers.register_command(bot, :archiveonly_file, 'Queue URLs from a file without recursion', guild_ids) do |cmd|
  cmd.string('url', 'URL pointing to the list of URLs', required: true)
  cmd.string('parameters', 'Optional job parameters', required: false)
end

DiscordCommandHelpers.register_command(bot, :status, 'Show the status for a job or URL', guild_ids) do |cmd|
  cmd.string('ident', 'Job identifier', required: false)
  cmd.string('url', 'URL previously queued for archival', required: false)
end

DiscordCommandHelpers.register_command(bot, :ignore, 'Add an ignore pattern to a job', guild_ids) do |cmd|
  cmd.string('ident', 'Job identifier', required: true)
  cmd.string('pattern', 'Pattern to add', required: true)
end

DiscordCommandHelpers.register_command(bot, :unignore, 'Remove an ignore pattern from a job', guild_ids) do |cmd|
  cmd.string('ident', 'Job identifier', required: true)
  cmd.string('pattern', 'Pattern to remove', required: true)
end

DiscordCommandHelpers.register_command(bot, :ignoreset, 'Apply ignore sets to a job', guild_ids) do |cmd|
  cmd.string('ident', 'Job identifier', required: true)
  cmd.string('sets', 'Comma separated set names', required: true)
end

DiscordCommandHelpers.register_command(bot, :expire, 'Expire a job', guild_ids) do |cmd|
  cmd.string('ident', 'Job identifier', required: true)
end

DiscordCommandHelpers.register_command(bot, :set_delay, 'Set delay bounds for a job', guild_ids) do |cmd|
  cmd.string('ident', 'Job identifier', required: true)
  cmd.integer('min', 'Minimum delay in milliseconds', required: true)
  cmd.integer('max', 'Maximum delay in milliseconds', required: true)
end

DiscordCommandHelpers.register_command(bot, :set_concurrency, 'Set concurrency for a job', guild_ids) do |cmd|
  cmd.string('ident', 'Job identifier', required: true)
  cmd.integer('level', 'Number of concurrent workers', required: true)
end

DiscordCommandHelpers.register_command(bot, :yahoo, 'Enable Yahoo! mode for a job', guild_ids) do |cmd|
  cmd.string('ident', 'Job identifier', required: true)
end

DiscordCommandHelpers.register_command(bot, :abort, 'Abort a job', guild_ids) do |cmd|
  cmd.string('ident', 'Job identifier', required: true)
end

DiscordCommandHelpers.register_command(bot, :ignore_reports, 'Toggle ignore pattern reports for a job', guild_ids) do |cmd|
  cmd.string('ident', 'Job identifier', required: true)
  cmd.boolean('enabled', 'Enable reports (true) or suppress them (false)', required: true)
end

DiscordCommandHelpers.register_command(bot, :pending, 'List pending jobs', guild_ids)

DiscordCommandHelpers.register_command(bot, :explain, 'Add a rationale to a job', guild_ids) do |cmd|
  cmd.string('ident', 'Job identifier', required: true)
  cmd.string('note', 'Explanation to record', required: true)
end

DiscordCommandHelpers.register_command(bot, :whereis, 'Show which pipeline is handling a job', guild_ids) do |cmd|
  cmd.string('ident', 'Job identifier', required: true)
end

bot.application_command(:archive) do |event|
  message = DiscordAdapters::Message.new(event)
  target = DiscordCommandHelpers.option(event, :url)
  params = DiscordCommandHelpers.option(event, :parameters) || ''
  brain.request_archive(message, target, params)
end

bot.application_command(:archive_file) do |event|
  message = DiscordAdapters::Message.new(event)
  target = DiscordCommandHelpers.option(event, :url)
  params = DiscordCommandHelpers.option(event, :parameters) || ''
  brain.request_archive(message, target, params, :inf, true)
end

bot.application_command(:archiveonly) do |event|
  message = DiscordAdapters::Message.new(event)
  target = DiscordCommandHelpers.option(event, :url)
  params = DiscordCommandHelpers.option(event, :parameters) || ''
  brain.request_archive(message, target, params, :shallow)
end

bot.application_command(:archiveonly_file) do |event|
  message = DiscordAdapters::Message.new(event)
  target = DiscordCommandHelpers.option(event, :url)
  params = DiscordCommandHelpers.option(event, :parameters) || ''
  brain.request_archive(message, target, params, :shallow, true)
end

bot.application_command(:status) do |event|
  message = DiscordAdapters::Message.new(event)
  ident = DiscordCommandHelpers.option(event, :ident)
  url = DiscordCommandHelpers.option(event, :url)

  if ident && !ident.empty?
    brain.find_job(ident, message) { |job| brain.request_status(message, job) }
  elsif url && !url.empty?
    brain.request_status_by_url(message, url)
  else
    message.safe_reply('Please provide either a job ident or a URL to check the status.')
  end
end

bot.application_command(:ignore) do |event|
  message = DiscordAdapters::Message.new(event)
  brain.find_job(DiscordCommandHelpers.option(event, :ident), message) do |job|
    brain.add_ignore_pattern(message, job, DiscordCommandHelpers.option(event, :pattern))
  end
end

bot.application_command(:unignore) do |event|
  message = DiscordAdapters::Message.new(event)
  brain.find_job(DiscordCommandHelpers.option(event, :ident), message) do |job|
    brain.remove_ignore_pattern(message, job, DiscordCommandHelpers.option(event, :pattern))
  end
end

bot.application_command(:ignoreset) do |event|
  message = DiscordAdapters::Message.new(event)
  brain.find_job(DiscordCommandHelpers.option(event, :ident), message) do |job|
    brain.add_ignore_sets(message, job, DiscordCommandHelpers.option(event, :sets))
  end
end

bot.application_command(:expire) do |event|
  message = DiscordAdapters::Message.new(event)
  brain.find_job(DiscordCommandHelpers.option(event, :ident), message) do |job|
    brain.expire(message, job)
  end
end

bot.application_command(:set_delay) do |event|
  message = DiscordAdapters::Message.new(event)
  brain.find_job(DiscordCommandHelpers.option(event, :ident), message) do |job|
    brain.set_delay(
      job,
      DiscordCommandHelpers.option(event, :min),
      DiscordCommandHelpers.option(event, :max),
      message
    )
  end
end

bot.application_command(:set_concurrency) do |event|
  message = DiscordAdapters::Message.new(event)
  brain.find_job(DiscordCommandHelpers.option(event, :ident), message) do |job|
    brain.set_concurrency(job, DiscordCommandHelpers.option(event, :level), message)
  end
end

bot.application_command(:yahoo) do |event|
  message = DiscordAdapters::Message.new(event)
  brain.find_job(DiscordCommandHelpers.option(event, :ident), message) do |job|
    brain.yahoo(job, message)
  end
end

bot.application_command(:abort) do |event|
  message = DiscordAdapters::Message.new(event)
  brain.find_job(DiscordCommandHelpers.option(event, :ident), message) do |job|
    brain.initiate_abort(message, job)
  end
end

bot.application_command(:ignore_reports) do |event|
  message = DiscordAdapters::Message.new(event)
  enabled = DiscordCommandHelpers.option(event, :enabled)
  brain.find_job(DiscordCommandHelpers.option(event, :ident), message) do |job|
    brain.toggle_ignores(message, job, enabled ? true : false)
  end
end

bot.application_command(:pending) do |event|
  message = DiscordAdapters::Message.new(event)
  brain.show_pending(message)
end

bot.application_command(:explain) do |event|
  message = DiscordAdapters::Message.new(event)
  brain.find_job(DiscordCommandHelpers.option(event, :ident), message) do |job|
    brain.add_note(message, job, DiscordCommandHelpers.option(event, :note))
  end
end

bot.application_command(:whereis) do |event|
  message = DiscordAdapters::Message.new(event)
  brain.find_job(DiscordCommandHelpers.option(event, :ident), message) do |job|
    brain.whereis(message, job)
  end
end

bot.run
