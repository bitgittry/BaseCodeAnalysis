DROP procedure IF EXISTS `MessageTemplateDeleteMessageGreeting`;

DELIMITER $$

CREATE PROCEDURE `MessageTemplateDeleteMessageGreeting`(messageGreetingID BIGINT(20))
BEGIN

DECLARE priorityToDelete INT(11);

	SELECT priority INTO priorityToDelete from gaming_message_greetings where message_greeting_id = messageGreetingID;

	UPDATE gaming_message_greetings
	SET priority = priority - 1
	WHERE priority > priorityToDelete AND is_hidden = 0;
                    
	UPDATE gaming_message_greetings
	SET is_hidden = 1
	WHERE message_greeting_id = messageGreetingID AND is_hidden = 0;

END$$

DELIMITER ;