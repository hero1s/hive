
local email_sender = curl.new_email_sender()

email_sender.set_smtp_server("mangguoyi445@163.com","QQLMFJBVAMYDAOQQ","smtp.163.com", "465");
email_sender.set_send_name("Server Dump Info");
email_sender.set_send_mail("mangguoyi445@163.com");
email_sender.add_recv_mail("8242117@qq.com");
email_sender.set_subject("TEST SUBJECT");
email_sender.set_body_content("fack you");
if email_sender.send_mail() then
    logger.debug("send mail success")
else
    logger.debug("send mail error")
end
