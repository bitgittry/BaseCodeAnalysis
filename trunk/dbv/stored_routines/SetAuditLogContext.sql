DROP procedure IF EXISTS SetAuditLogContext;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SetAuditLogContext`(modifierEntityType VARCHAR(45), modifierEntityExtraId BIGINT, sessionId BIGINT, clientChangeReasonId BIGINT, customReason VARCHAR(512))
BEGIN
SET @modifierEntityType = modifierEntityType;
SET @modifierEntityExtraId = modifierEntityExtraId;
SET @auditLogSessionId = sessionId;
SET @clientChangeReasonId = clientChangeReasonId;
SET @customReason = customReason;
END$$

DELIMITER ;
