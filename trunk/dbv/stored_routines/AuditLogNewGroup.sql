DROP function IF EXISTS `AuditLogNewGroup`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `AuditLogNewGroup`(extraID BIGINT(20), sessionID BIGINT(20), subjectEntityId BIGINT(20), auditLogTypeId INT(11), modifierEntityType VARCHAR(45), clientChangeReasonId BIGINT(20), customReason VARCHAR(512), clientId BIGINT(20)) RETURNS bigint(20)
BEGIN

	DECLARE modifierEntityId, auditLogGroupId BIGINT DEFAULT -1; 

	SET extraID=IFNULL(extraID, 0);
	SELECT modifier_entity_id INTO modifierEntityId FROM gaming_modifier_entities WHERE type = modifierEntityType AND extra_id = extraID;

	IF (modifierEntityId = -1) THEN
	  INSERT INTO gaming_modifier_entities(type, extra_id)
	  VALUES (modifierEntityType, extraID);
	SET modifierEntityId = LAST_INSERT_ID();
	END IF;

    INSERT INTO gaming_client_audit_log_groups(client_audit_log_type, subject_id, modifier_entity_id, timestamp, client_change_reason_id, custom_reason, session_id, client_id)
    VALUES(auditLogTypeId, subjectEntityId, modifierEntityId, NOW(), clientChangeReasonId, customReason, sessionID, IFNULL(clientId, 0));
	
    RETURN LAST_INSERT_ID();
    
END$$

DELIMITER ;

