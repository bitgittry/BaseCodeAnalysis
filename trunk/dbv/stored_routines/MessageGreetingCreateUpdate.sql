DROP procedure IF EXISTS `MessageGreetingCreateUpdate`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `MessageGreetingCreateUpdate`(messageGreetingID BIGINT(20), messageTemplateSetID BIGINT(20), notificationEventTypeID INT(11), playerSelectionID BIGINT(20), displayName VARCHAR(50), PriorityVar INT(11), DescriptionVar VARCHAR(500),  dateFrom DATETIME,  dateTo DATETIME,  createdByUserID BIGINT(20), changedByUserID BIGINT(20), isNeverEnding TINYINT(1), enableLogging TINYINT(1), OUT statusCode INT,  OUT lastInsertID BIGINT(20))
root: BEGIN

DECLARE highestPriority INT(11);
DECLARE priorityToInsert INT(11);
DECLARE oldPriority INT(11);
DECLARE titleAlreadyExists INT(4);

SET priorityToInsert = PriorityVar;
SET statusCode = 0;

IF (messageGreetingID IS NULL) THEN
  
    -- If the title (display name) to be inserted already exists, do not insert
   SELECT COUNT(*) INTO titleAlreadyExists FROM gaming_message_greetings where display_name = displayName AND is_hidden = 0;
	IF (titleAlreadyExists > 0) THEN 
		SET statusCode = 2;
		LEAVE root;
	ELSE

		-- If there are already records in the table
		IF  (SELECT COUNT(priority) FROM gaming_message_greetings WHERE is_hidden = 0) > 0 THEN

			SELECT priority INTO highestPriority FROM gaming_message_greetings WHERE is_hidden = 0 ORDER BY priority DESC LIMIT 1;

				-- If the priority to be inserted is higher than the highest priority already present, set the new priority to highest + 1
		IF (PriorityVar > (highestPriority + 1)) THEN 
		SET priorityToInsert = highestPriority + 1;
		SET statusCode = 1;
  
		-- Else if priority to be inserted is less than the highest priority already present
		ELSE 
		UPDATE gaming_message_greetings 
		SET priority = priority + 1
		WHERE priority >= PriorityVar AND is_hidden = 0
		ORDER BY priority DESC;
		END IF;


		INSERT INTO gaming_message_greetings (message_template_set_id,notification_event_type_id,player_selection_id,display_name,priority,description,date_from,date_to,created_by_user_id, created_on, changed_by_user_id, changed_on, is_never_ending, enable_logging)
		VALUES  (messageTemplateSetID, notificationEventTypeID, playerSelectionID, displayName, priorityToInsert, DescriptionVar,dateFrom,IF(isNeverEnding,null,dateTo),createdByUserID, NOW(), null, null, isNeverEnding, enableLogging);
		SET lastInsertID = LAST_INSERT_ID();
		
		-- If it is the first entry in the table, set the priority to 1
		ELSE 
		SET @priorityToInsert = 1;
		INSERT INTO gaming_message_greetings (message_template_set_id,notification_event_type_id,player_selection_id,display_name,priority,description,date_from,date_to,created_by_user_id, created_on, changed_by_user_id, changed_on, is_never_ending, enable_logging)
		VALUES  (messageTemplateSetID, notificationEventTypeID, playerSelectionID, displayName, @priorityToInsert, DescriptionVar,dateFrom,IF(isNeverEnding,null,dateTo),createdByUserID, NOW(), null, null, isNeverEnding, enableLogging);
		SET lastInsertID = LAST_INSERT_ID();
	END IF;
  
END IF;

ELSE
  
  SELECT priority INTO oldPriority FROM gaming_message_greetings WHERE gaming_message_greetings.message_greeting_id = messageGreetingID ;
  
  SELECT priority INTO highestPriority FROM gaming_message_greetings WHERE is_hidden = 0 ORDER BY priority DESC LIMIT 1;
	
  -- IF the title to be updated matches to another title of another greeting already present in the table, do not update record
  SELECT COUNT(*) INTO titleAlreadyExists FROM gaming_message_greetings where display_name = displayName AND message_greeting_id != messageGreetingID AND is_hidden = 0; 

IF (titleAlreadyExists > 0) THEN 
		SET statusCode = 2;
		LEAVE root;
	ELSE

  
	IF (oldPriority > priorityToInsert) THEN
		UPDATE gaming_message_greetings 
		SET priority = priority + 1
		WHERE priority >= priorityToInsert AND priority < oldPriority AND is_hidden = 0;

	ELSE IF (oldPriority < priorityToInsert AND priorityToInsert < highestPriority) THEN
		UPDATE gaming_message_greetings 
		SET priority = priority - 1
		WHERE priority <= priorityToInsert AND priority > oldPriority AND is_hidden = 0;
   
   ELSE IF (oldPriority < priorityToInsert AND priorityToInsert > highestPriority) THEN
		UPDATE gaming_message_greetings 
		SET priority = priority - 1
		WHERE priority <= priorityToInsert AND priority > oldPriority AND is_hidden = 0;
		SET priorityToInsert = highestPriority;
		SET statusCode = 1;
   ELSE IF (oldPriority = priorityToInsert) THEN
		SET priorityToInsert = oldPriority;
   ELSE 
		SET priorityToInsert = highestPriority;
   END If;
   END IF;
   END IF;
  END IF;
END IF;

  UPDATE  gaming_message_greetings SET message_template_set_id = messageTemplateSetID,notification_event_type_id = notificationEventTypeID,
   player_selection_id = playerSelectionID,display_name = displayName,priority = priorityToInsert,description =  DescriptionVar,
   date_from = dateFrom,date_to = IF(isNeverEnding,null,dateTo),changed_by_user_id = changedByUserID, changed_on = NOW(), is_never_ending = isNeverEnding, enable_logging = enableLogging
   WHERE gaming_message_greetings.message_greeting_id = messageGreetingID;
   SET lastInsertID = messageGreetingID;
 END IF;
END$$

DELIMITER ;

