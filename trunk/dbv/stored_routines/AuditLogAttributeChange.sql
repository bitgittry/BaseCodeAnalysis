DROP procedure IF EXISTS `AuditLogAttributeChange`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `AuditLogAttributeChange`(attrName VARCHAR(255), subjectId BIGINT, logGroupId BIGINT, newValue VARCHAR(1024), oldValue VARCHAR(1024), effectiveDate DATETIME)
BEGIN
DECLARE addRes INT; 
SELECT AuditLogAttributeChangeFunc(attrName, subjectId, logGroupId, newValue, oldValue, effectiveDate) INTO addRes;
END$$

DELIMITER ;

