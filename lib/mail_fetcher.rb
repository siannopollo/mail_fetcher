require File.dirname(__FILE__) + "/net/pop"
require File.dirname(__FILE__) + "/net/imap"
require "yaml"

class MailFetcher
  class << self
    attr_accessor :mailer_class, :config, :access
    
    def mailer_class
      @mailer_class.to_s.classify.constantize unless @mailer_class.nil?
    end
    
    # Configuration options:
    # * <tt>mailer_methods</tt> - An array of symbols of the methods you wish the mailer_class to invoke on each
    #   fetched email. Defaults to :receive.
    # * <tt>keep</tt> - Tells the fetcher whether to keep the emails. :keep => true keeps the fetcher from
    #   deleting emails. :keep is implied to be true if :delete_if is used. Fetcher will delete all mail by default.
    # * <tt>delete_if</tt> - A block to pass in that is run against each email to determine whether it should be
    #   deleted from the server. If the block evaluates to true, the email is deleted. All other emails are left intact.
    # * <tt>env</tt> - Tells the fetcher which configuration in mailer.yml to use. Defaults to ENV["RAILS_ENV"].
    # * <tt>finish</tt> - So, the Net::POP docs say to close the connection with pop#finish, but for some odd
    #   reason calling the below function when connected to GMail resets POP3 access and won't allow you to reconnect.
    #   This plugin was tested with a GMail account, hence the need for this option.
    # * <tt>use_imap</tt> - Used in conjunction with IMAP, in that it passes the IMAP object to the
    #   mailer_class to do whatever it wishes with the connection (since IMAP allows for more features than POP3).
    #   Just pass in the name of the method(s) to pass the IMAP object to: :use_imap => :process_with_imap.
    def fetch(options={})
      options = prepare_options(options)
      check_mailer!(options)
      self.config ||= YAML.load_file("#{RAILS_ROOT}/config/mail_fetcher.yml")[options[:env] || ENV["RAILS_ENV"]]
      send :"fetch_#{access || "imap"}", options
    end
    
    def fetch_pop(options={})
      Net::POP3.enable_ssl(OpenSSL::SSL::VERIFY_NONE)
      pop = Net::POP3.new(config[:server]).start(config[:username], config[:password])
      
      pop.mails.each do |mail|
        email = TMail::Mail.parse(mail.pop)
        [options[:mailer_methods]].flatten.each {|method| mailer_class.send(method, email)}
        mail.delete if (options[:delete_if] && options[:delete_if].call(email))
        mail.delete unless options[:keep]
      end
      pop.finish if options[:finish]
    end
    
    def fetch_imap(options={})
      imap = Net::IMAP.new(config[:server], config[:port], true)
      imap.login(config[:username], config[:password])
      
      if options[:use_imap]
        [options[:use_imap]].flatten.each {|method| mailer_class.send(method, imap)}
      else
        imap.examine('INBOX')
        imap.search(['ALL']).each do |message_id|
          email = TMail::Mail.parse(imap.fetch(message_id,'RFC822')[0].attr['RFC822'])
          [options[:mailer_methods]].flatten.each {|method| mailer_class.send(method, email)}
          imap.store(message_id, "+FLAGS", [:Deleted]) if (options[:delete_if] && options[:delete_if].call(email))
          imap.store(message_id, "+FLAGS", [:Deleted]) unless options[:keep]
        end
        imap.close
      end
    end
    
    protected
    def check_mailer!(options={})
      raise NoMailerError if mailer_class.nil?
      raise MailerClassInterfaceError if ([options[:mailer_methods]].flatten.size == 1 && !mailer_class.respond_to?(:receive))
    end
    
    def prepare_options(options)
      returning options do |opts|
        opts[:mailer_methods] ||= :receive
        opts[:keep] = true if opts[:delete_if]
        opts[:finish] ||= false
      end
    end
  end
  
  class NoMailerError < StandardError
    def message
      "A mailer_class must be defined before you can fetch mail"
    end
  end
  
  class MailerClassInterfaceError < StandardError
    def message
      "The mailer_class should at least respond to #receive.\nAlternately, try passing in :mailer_methods => [:method1, :method2] to MailFetcher.fetch"
    end
  end
end
