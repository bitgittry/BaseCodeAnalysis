DROP procedure IF EXISTS `PlayerSetKYCFlag`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerSetKYCFlag`(clientID BIGINT, isKycChecked TINYINT(1), kycCheckedStatusCode INT(4), userID BIGINT)
root: BEGIN
  -- first version
  -- Committing to DBV
  -- Limiting 1 when retrieving KYC status just in case  

  DECLARE curKycChecked TINYINT(1) DEFAULT 0;
  DECLARE curKycCheckedStatus INT(4) DEFAULT NULL;
  DECLARE isKycCheckedStatusFinal TINYINT(1);
  DECLARE kycCheckedStatusID BIGINT(20) DEFAULT NULL;
  DECLARE auditLogGroupId BIGINT;
  
  SELECT is_kyc_checked INTO curKycChecked FROM gaming_clients WHERE client_id=clientID;
  SELECT gaming_kyc_checked_statuses.status_code INTO curKycCheckedStatus FROM  gaming_kyc_checked_statuses 
  JOIN gaming_clients ON gaming_kyc_checked_statuses.kyc_checked_status_id = gaming_clients.kyc_checked_status_id 
   WHERE client_id=clientID;

  SELECT is_kyc_checked INTO isKycCheckedStatusFinal FROM gaming_kyc_checked_statuses WHERE status_code = kycCheckedStatusCode LIMIT 1;
	
  IF(isKycChecked IS NULL) THEN
	   SET isKycChecked = IFNULL(isKycCheckedStatusFinal, curKycChecked);
  END IF;
    
   IF ((isKycChecked=curKycChecked) AND (curKycCheckedStatus=kycCheckedStatusCode) OR (kycCheckedStatusCode IS NULL AND (isKycChecked=curKycChecked))) THEN
	LEAVE root;
  END IF;

  SELECT kyc_checked_status_id INTO kycCheckedStatusID FROM  gaming_kyc_checked_statuses WHERE status_code=kycCheckedStatusCode LIMIT 1;
   
  UPDATE gaming_clients SET last_updated_flags=NOW(), 
  is_kyc_checked=isKycChecked, 
  kyc_checked_status_id = kycCheckedStatusID, 
  kyc_checked_date = IF(curKycChecked = isKycChecked, kyc_checked_date, IF(isKycChecked=1, NOW(), NULL))
  WHERE client_id=clientID; 

  -- Log Change
  SET userID=IFNULL(userID, 0);
  SET auditLogGroupId = AuditLogNewGroup(userID, NULL, clientID, 10, IF(userID=0, 'System', 'User'), NULL, NULL, clientID);
  CALL AuditLogAttributeChange('KYC Checked', clientID, auditLogGroupId, isKycChecked, curKycChecked, NOW());
    
  -- push notification
  CALL NotificationEventCreate(8, clientID, NULL, 0);

END root$$

DELIMITER ;

