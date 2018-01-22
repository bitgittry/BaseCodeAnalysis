DROP procedure IF EXISTS `PlayerUpdateUAData`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerUpdateUAData`(userID BIGINT, sessionID BIGINT, clientID BIGINT,
 uaBrandID BIGINT, uaModelID BIGINT, uaOSID BIGINT, uaOSVersionID BIGINT, uaBrowserID BIGINT, uaBrowserVersionID BIGINT, uaEngineID BIGINT, uaEngineVersionID BIGINT)
BEGIN
  
  DECLARE curUABrandID, curUAModelID, curUAOSID, curUAOSVersionID, curUABrowserID, curUABrowserVersionID, curUAEngineID, curUAEngineVersionID BIGINT DEFAULT -1;
  DECLARE 
	curUABrandName, uaBrandName, 
    curUAModelName, uaModelName,
    curUAOSName, uaOSName,
    curUAOSVersionName, uaOSVersionName,
    curUABrowserName, uaBrowserName,
    curUABrowserVersionName, uaBrowserVersionName,
    curUAEngineName, uaEngineName,
    curUAEngineVersionName, uaEngineVersionName
    VARCHAR(50) DEFAULT '';
  DECLARE auditLogGroupId BIGINT DEFAULT -1;
  
  SELECT ua_brand_id, ua_model_id, ua_os_id, ua_os_version_id, ua_browser_id, ua_browser_version_id, ua_engine_id, ua_engine_version_id
  INTO curUABrandID, curUAModelID, curUAOSID, curUAOSVersionID, curUABrowserID, curUABrowserVersionID, curUAEngineID, curUAEngineVersionID
  FROM gaming_client_ua_registrations WHERE client_id=clientID;

  SET userID=IFNULL(userID, 0);

	-- New version of audit logs
	
    SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 2, 'User', NULL, NULL,clientID);

  IF (uaBrandID IS NOT NULL) THEN
	IF (curUABrandID!=uaBrandID) THEN
		INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before)
		VALUES (clientID, userID, now(), 'UA Brand', uaBrandID, curUABrandID);
        SELECT `name` into uaBrandName FROM gaming_ua_brands where ua_brand_id = uaBrandID;
        SELECT `name` into curUABrandName FROM gaming_ua_brands where ua_brand_id = curUABrandID;
		CALL AuditLogAttributeChange('UA Brand', clientID, auditLogGroupId, uaBrandName, curUABrandName, NOW());
	END IF;
  END IF; 
  IF (uaModelID IS NOT NULL) THEN
	IF (curUAModelID!=uaModelID) THEN
		INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before)
		VALUES (clientID, userID, now(), 'UA Model', uaModelID, curUAModelID);
		SELECT `name` into uaModelName FROM gaming_ua_models where ua_model_id = uaModelID;
        SELECT `name` into curUAModelName FROM gaming_ua_models where ua_model_id = curUAModelID;
		CALL AuditLogAttributeChange('UA Model', clientID, auditLogGroupId, uaModelName, curUAModelName, NOW());
	END IF;
  END IF;
  IF (uaOSID IS NOT NULL) THEN
	IF (curUAOSID!=uaOSID) THEN
		INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before)
		VALUES (clientID, userID, now(), 'UA OS', uaOSID, curUAOSID);
        SELECT `name` into uaOSName FROM gaming_ua_os where ua_os_id = uaOSID;
        SELECT `name` into curUAOSName FROM gaming_ua_os where ua_os_id = curUAOSID;
		CALL AuditLogAttributeChange('UA OS', clientID, auditLogGroupId, uaOSName, curUAOSName, NOW());
	END IF;
  END IF;
  IF (uaOSVersionID IS NOT NULL) THEN
	IF (curUAOSVersionID!=uaOSVersionID) THEN
		INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before)
		VALUES (clientID, userID, now(), 'UA OS Version', uaOSVersionID, curUAOSVersionID);
        SELECT `name` into uaOSVersionName FROM gaming_ua_os_versions where ua_os_version_id = uaOSVersionID;
        SELECT `name` into curUAOSVersionName FROM gaming_ua_os_versions where ua_os_version_id = curUAOSVersionID;
		CALL AuditLogAttributeChange('UA OS Version', clientID, auditLogGroupId, uaOSVersionName, curUAOSVersionName, NOW());
	END IF;
  END IF;
  IF (uaBrowserID IS NOT NULL) THEN
	IF (curUABrowserID!=uaBrowserID) THEN
		INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before)
		VALUES (clientID, userID, now(), 'UA Browser', uaBrowserID, curUABrowserID);
        SELECT `name` into uaBrowserName FROM gaming_ua_browsers where ua_browser_id = uaBrowserID;
        SELECT `name` into curUABrowserName FROM gaming_ua_browsers where ua_browser_id = curUABrowserID;
		CALL AuditLogAttributeChange('UA Browser', clientID, auditLogGroupId, uaBrowserName, curUABrowserName, NOW());
	END IF;
  END IF;	
  IF (uaBrowserVersionID IS NOT NULL) THEN
	IF (curUABrowserVersionID!=uaBrowserVersionID) THEN
		INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before)
		VALUES (clientID, userID, now(), 'UA Browser Version', uaBrowserVersionID, curUABrowserVersionID);
        SELECT `name` into uaBrowserVersionName FROM gaming_ua_browser_versions where ua_browser_version_id = uaBrowserVersionID;
        SELECT `name` into curUABrowserVersionName FROM gaming_ua_browser_versions where ua_browser_version_id = curUABrowserVersionID;
		CALL AuditLogAttributeChange('UA Browser Version', clientID, auditLogGroupId, uaBrowserVersionName, curUABrowserVersionName, NOW());
	END IF;
  END IF;
  IF (uaEngineID IS NOT NULL) THEN
	IF (curUAEngineID!=uaEngineID) THEN
		INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before)
		VALUES (clientID, userID, now(), 'UA Engine', uaEngineID, curUAEngineID);
		SELECT `name` into uaEngineName FROM gaming_ua_engines where ua_engine_id = uaEngineID;
        SELECT `name` into curUAEngineName FROM gaming_ua_engines where ua_engine_id = curUAEngineID;
		CALL AuditLogAttributeChange('UA Engine', clientID, auditLogGroupId, uaEngineName, curUAEngineName, NOW());
	END IF;
  END IF;
  IF (uaEngineVersionID IS NOT NULL) THEN
	IF (curUAEngineVersionID!=uaEngineVersionID) THEN
		INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before)
		VALUES (clientID, userID, now(), 'UA Engine Version', uaEngineVersionID, curUAEngineVersionID);
        SELECT `name` into uaEngineVersionName FROM gaming_ua_engine_versions where ua_engine_version_id = uaEngineVersionID;
        SELECT `name` into curUAEngineVersionName FROM gaming_ua_engine_versions where ua_engine_version_id = curUAEngineVersionID;
		CALL AuditLogAttributeChange('UA Engine Version', clientID, auditLogGroupId, uaEngineVersionName, curUAEngineVersionName, NOW());
	END IF;
  END IF;	 

  INSERT gaming_client_ua_registrations (client_id, ua_brand_id, ua_model_id, ua_os_id, ua_os_version_id, ua_browser_id, ua_browser_version_id, ua_engine_id, ua_engine_version_id)
  VALUES (clientID, uaBrandID, uaModelID, uaOSID, uaOSVersionID, uaBrowserID, uaBrowserVersionID, uaEngineID, uaEngineVersionID)
  ON DUPLICATE KEY UPDATE ua_brand_id=IFNULL(uaBrandID, ua_brand_id), ua_model_id=IFNULL(uaModelID, ua_model_id), ua_os_id=IFNULL(uaOSID, ua_os_id),
	ua_os_version_id=IFNULL(uaOSVersionID, ua_os_version_id), ua_browser_id=IFNULL(uaBrowserID, ua_browser_id), ua_browser_version_id=IFNULL(uaBrowserVersionID, ua_browser_version_id), ua_engine_id=IFNULL(uaEngineID, ua_engine_id), ua_engine_version_id=IFNULL(uaEngineVersionID, ua_engine_version_id);


END$$

DELIMITER ;

