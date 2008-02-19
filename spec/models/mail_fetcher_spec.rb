require File.dirname(__FILE__) + '/../spec_helper'

describe MailFetcher do
  it "should exist" do
    MailFetcher.should be_a_kind_of(Class)
  end
  
  it "should raise error if the mailer class isn't set when trying to fetch" do
    lambda{MailFetcher.fetch}.should raise_error(MailFetcher::NoMailerError)
  end
  
  describe "mailer class" do
    class MailyMcMailer; end
    
    it "should exist" do
      MailFetcher.should respond_to(:mailer_class)
    end
    
    it "should be set" do
      MailFetcher.mailer_class = :maily_mc_mailer
      MailFetcher.mailer_class.should == MailyMcMailer
    end
    
    describe "interface" do
      before(:each) do
        MailFetcher.mailer_class = :maily_mc_mailer
      end
      
      it "should respond to receive if no mailer_methods are passed in" do
        block = lambda {MailFetcher.send(:check_mailer!, :mailer_methods => [:receive])}
        block.should raise_error(MailFetcher::MailerClassInterfaceError)
        
        MailyMcMailer.should_receive(:respond_to?).with(:receive).and_return(true)
        block = lambda {MailFetcher.send(:check_mailer!, :mailer_methods => [:receive])}
        block.should_not raise_error(MailFetcher::MailerClassInterfaceError)
      end
    end
  end
  
  describe "fetching" do
    before(:all) do
      ActionMailer::Base.delivery_method = :smtp
      ActionMailer::Base.perform_deliveries = true
      ActionMailer::Base.smtp_settings = {
        :address        => "smtp.gmail.com", 
        :port           => 587, 
        :domain         => nil, 
        :user_name      => "mail.fetcher.test@gmail.com", 
        :password       => "mailfetchertest", 
        :authentication => :login
      }
      
      MailFetcher.mailer_class = :mailer
    end
    
    
    describe "POP access" do
      before(:all) do
        MailFetcher.config = {
          :server   => "pop.gmail.com",
          :username => "mail.fetcher.test@gmail.com",
          :password => "mailfetchertest"
        }
        MailFetcher.access = :pop
      end
      
      after(:each) do
        Mailer::EMAILS.clear
      end
      
      it "should fetch emails from the specified email" do
        Mailer.deliver_test_email
        Mailer::EMAILS.size.should == 0
        MailFetcher.fetch
        Mailer::EMAILS.size.should > 0
      end
      
      it "should not delete emails if :keep is true" do
        Mailer.deliver_test_email
        Mailer::EMAILS.size.should == 0
        MailFetcher.fetch(:keep => true)
        size = Mailer::EMAILS.size
        size.should > 0
        
        MailFetcher.fetch
        Mailer::EMAILS.size.should > size
      end
      
      it "should allow a block to be passed to determine if an email should be deleted" do
        Mailer::EMAILS.size.should == 0
        subject = "G'day mate! - #{Time.now.strftime("%I:%M %p")}"
        Mailer.deliver_test_email(:subject => subject)
        
        delete_if = lambda {|email| email.subject =~ /#{Regexp.escape(subject)}/}
        MailFetcher.fetch(:delete_if => delete_if)
        
        Mailer::EMAILS.clear
        MailFetcher.fetch
        Mailer::EMAILS.select {|e| e.subject =~ /#{Regexp.escape(subject)}/}.size.should == 0
      end
    end
    
    describe "IMAP access" do
      before(:all) do
        MailFetcher.config = {
          :server   => "imap.gmail.com",
          :port     => 993,
          :username => "mail.fetcher.test@gmail.com",
          :password => "mailfetchertest"
        }
        MailFetcher.access = :imap
      end
      
      before(:each) do
        Mailer::EMAILS.clear
        Mailer::IMAP_EMAILS.clear
      end
      
      it "should fetch emails from the specified address" do
        Mailer.deliver_test_email
        Mailer::EMAILS.size.should == 0
        MailFetcher.fetch
        Mailer::EMAILS.size.should > 0
      end
      
      it "should not delete emails if :keep is true" do
        Mailer.deliver_test_email
        Mailer::EMAILS.size.should == 0
        MailFetcher.fetch(:keep => true)
        size = Mailer::EMAILS.size
        size.should > 0
        
        MailFetcher.fetch
        Mailer::EMAILS.size.should > size
      end
      
      it "should allow a block to be passed to determine if an email should be deleted" do
        Mailer::EMAILS.size.should == 0
        subject = "G'day mate! - #{Time.now.strftime("%I:%M %p")}"
        Mailer.deliver_test_email(:subject => subject)
        
        delete_if = lambda {|email| email.subject =~ /#{Regexp.escape(subject)}/}
        MailFetcher.fetch(:delete_if => delete_if)
        
        Mailer::EMAILS.clear
        MailFetcher.fetch
        Mailer::EMAILS.select {|e| e.subject =~ /#{Regexp.escape(subject)}/}.size.should == 0
      end
      
      it "should allow the imap object to be passed to the mailer_class to do whatever it wishes with the connection" do
        Mailer.deliver_test_email
        Mailer::IMAP_EMAILS.size.should == 0
        Mailer::EMAILS.size.should == 0
        
        MailFetcher.fetch(:use_imap => :process_with_imap)
        Mailer::IMAP_EMAILS.size.should > 0
        Mailer::EMAILS.size.should == 0
      end
    end
  end
end

class Mailer < ActionMailer::Base
  EMAILS = []
  IMAP_EMAILS = []
  
  def test_email(options={})
    @recipients, @from, @subject = 
    (options[:recipients] || "mail.fetcher.test@gmail.com"),
    (options[:from] || "the_test@example.com"),
    (options[:subject] || "Just Testing")
  end
  
  def render_message(method_name, body)
    "Let me know if this works... please?"
  end
  
  def self.receive(email)
    Mailer::EMAILS << email
  end
  
  def self.process_with_imap(imap)
    imap.examine('INBOX')
    imap.search(['ALL']).each do |message_id|
      IMAP_EMAILS << TMail::Mail.parse(imap.fetch(message_id,'RFC822')[0].attr['RFC822'])
      imap.store(message_id, "+FLAGS", [:Deleted])
    end
    imap.close
  end
end
