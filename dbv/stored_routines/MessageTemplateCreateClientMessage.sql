DROP procedure IF EXISTS `MessageTemplateCreateClientMessage`;

DELIMITER $$
CREATE DEFINER=`root`@`localhost` PROCEDURE `MessageTemplateCreateClientMessage`(
  messageGreetingID BIGINT(20), messageGreetingTitle VARCHAR(40), clientID BIGINT(20), messageTemplateID BIGINT(20), languageID VARCHAR(3), 
  platformTypeID TINYINT(4),sentMessage TINYTEXT, eventID BIGINT(20))
BEGIN

	INSERT INTO gaming_client_template_messages (message_greeting_id,message_greeting_title, client_id, timestamp,message_template_id, platform_type_id, language_id, sent_message, event_id)
	VALUES  (messageGreetingID, messageGreetingTitle, clientID, NOW(), messageTemplateID, platformTypeID, languageID, sentMessage, eventID);
    
END$$

DELIMITER ;

