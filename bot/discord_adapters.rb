# Lightweight wrappers that provide the minimal API surface required by
# ArchiveBot's Brain when handling Discord slash command interactions.
module DiscordAdapters
  # Wraps a Discord slash command interaction so it looks like a Cinch message.
  class Message
    def initialize(event)
      @event = event
      @responded = false
      @user = User.new(event, self)
      @channel = Channel.new(event)
    end

    attr_reader :event
    attr_reader :user
    attr_reader :channel

    def safe_reply(message, _allow_private = false)
      deliver(message, ephemeral: false)
    end

    def send_ephemeral(message)
      deliver(message, ephemeral: !!event.server)
    end

    private

    def deliver(message, ephemeral:)
      if responded?
        if event.respond_to?(:send_followup_message)
          event.send_followup_message(content: message, ephemeral: ephemeral)
        else
          event.respond(content: message)
        end
      else
        event.respond(content: message, ephemeral: ephemeral)
        @responded = true
      end
    end

    def responded?
      @responded || event.responded?
    rescue NoMethodError
      @responded
    end
  end

  # Presents the Discord user like a Cinch user.
  class User
    def initialize(event, message)
      @event = event
      @message = message
      @member = event.server&.member(event.user.id)
    end

    def nick
      @member&.display_name || @event.user.username
    end

    def safe_send(message)
      @message.send_ephemeral(message)
    end

    def permission?(permission)
      return false unless @member

      @member.permission?(permission)
    end
  end

  # Provides the subset of Cinch::Channel used by Brain.
  class Channel
    def initialize(event)
      @event = event
      @channel = event.channel
    end

    def name
      return 'Direct Message' unless @channel

      if @channel.respond_to?(:name) && @channel.name
        "##{@channel.name}"
      else
        @channel.to_s
      end
    end

    def opped?(user)
      return true unless @event.server

      user.permission?(:administrator) || user.permission?(:manage_guild)
    end

    def voiced?(user)
      return true unless @event.server

      opped?(user) || user.permission?(:manage_messages) ||
        user.permission?(:moderate_members)
    end
  end
end
