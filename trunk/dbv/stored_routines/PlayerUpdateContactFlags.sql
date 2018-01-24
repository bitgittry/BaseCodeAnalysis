DROP procedure IF EXISTS `PlayerUpdateContactFlags`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerUpdateContactFlags`(
  userID BIGINT, sessionID BIGINT, clientID BIGINT, contactByEmail TINYINT(1), contactBySMS TINYINT(1), 
  contactByPost TINYINT(1), contactByPhone TINYINT(1), contactByMobile TINYINT(1), contactByThirdParty TINYINT(1), forceUpdateDetails TINYINT(1), 
  INOUT changeDetected TINYINT(1))
BEGIN

   -- Added push notification
   
   DECLARE curContactByEmail, curContactBySMS, curContactByPost, curContactByPhone, curContactByMobile, curContactByThirdParty TINYINT(1) DEFAULT 0;
   DECLARE changeNo INT DEFAULT NULL;
   DECLARE auditLogGroupId BIGINT DEFAULT -1;
   DECLARE modifierEntityType VARCHAR(45);
 
   SET modifierEntityType = IFNULL(@modifierEntityType, 'System');
   SET userID=IFNULL(userID, 0);

    -- New version of audit logs
    

	  SELECT contact_by_email, contact_by_sms, contact_by_post, contact_by_phone, contact_by_mobile, contact_by_third_party, num_details_changes+1
	  INTO curContactByEmail, curContactBySMS, curContactByPost, curContactByPhone, curContactByMobile, curContactByThirdParty, changeNo
	  FROM gaming_clients WHERE client_id=clientID;

	  IF (contactByEmail IS NOT NULL) THEN
		IF (curContactByEmail!=contactByEmail) THEN
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Contact By Email', contactByEmail, curContactByEmail, changeNo);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId= AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('Contact By Email', clientID, auditLogGroupId, contactByEmail, curContactByEmail, NOW());
		END IF;
	  END IF;
	  IF (contactBySMS IS NOT NULL) THEN
		IF (curContactBySMS!=contactBySMS) THEN
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Contact By SMS', contactBySMS, curContactBySMS, changeNo);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId= AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('Contact By SMS', clientID, auditLogGroupId, contactBySMS, curContactBySMS, NOW());
		END IF;
	  END IF;
	  IF (contactByPost IS NOT NULL) THEN
		IF (curContactByPost!=contactByPost) THEN
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Contact By Post', contactByPost, curContactByPost, changeNo);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId= AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('Contact By Post', clientID, auditLogGroupId, contactByPost, curContactByPost, NOW());
		END IF;
	  END IF;
	  IF (contactByPhone IS NOT NULL) THEN
		IF (curContactByPhone!=contactByPhone) THEN
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Contact By Phone', contactByPhone, curContactByPhone, changeNo);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId= AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('Contact By Phone', clientID, auditLogGroupId, contactByPhone, curContactByPhone, NOW());
		END IF;
	  END IF;
	  IF (contactByMobile IS NOT NULL) THEN
		IF (curContactByMobile!=contactByMobile) THEN
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Contact By Mobile', contactByMobile, curContactByMobile, changeNo);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId= AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('Contact By Mobile', clientID, auditLogGroupId, contactByMobile, curContactByMobile, NOW());
		END IF;
	  END IF;
	  IF (contactByThirdParty IS NOT NULL) THEN
		IF (curContactByThirdParty!=contactByThirdParty) THEN
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Contact By Third Party', contactByThirdParty, curContactByThirdParty, changeNo);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId= AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('Contact By Third Party', clientID, auditLogGroupId, contactByThirdParty, curContactByThirdParty, NOW());
		END IF;
	  END IF;

  IF (IFNULL(forceUpdateDetails, 0) = 1)
    THEN
    UPDATE gaming_clients 
    SET contact_by_email=IFNULL(contactByEmail, contact_by_email), contact_by_sms=IFNULL(contactBySMS, contact_by_sms), contact_by_post=IFNULL(contactByPost, contact_by_post), contact_by_phone=IFNULL(contactByPhone, contact_by_phone), contact_by_mobile=IFNULL(contactByMobile, contact_by_mobile), contact_by_third_party=IFNULL(contactByThirdParty, contact_by_third_party),
  	  session_id=sessionID, last_updated=NOW(), num_details_changes=IF(changeDetected, changeNo, num_details_changes)
    WHERE client_id=clientID;
   END IF;
   
   CALL NotificationEventCreate(3, clientID, NULL, 0);
   CALL NotificationEventCreate(614, clientID, NULL, 0);

END$$

DELIMITER ;

