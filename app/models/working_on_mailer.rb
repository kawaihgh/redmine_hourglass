class WorkingOnMailer < ActionMailer::Base
  class << self
    def deliver_now(user, issue)
      ::WorkingOnMailer.now(user, issue).deliver
    end
  end


  def now(user, issue)
    @user  = user
    @issue = issue

    mail(:from    =>  user.mail,
         :to      => 'today@m.workingon.co',
         :subject => "Working On #{::Time.now.strftime('%Y/%m/%d %H:%M:%S')}") do |format|
      format.text
    end
  end
end
