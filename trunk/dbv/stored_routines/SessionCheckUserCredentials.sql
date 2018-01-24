DROP procedure IF EXISTS `SessionCheckUserCredentials`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SessionCheckUserCredentials`(varUsername VARCHAR(255), varPassword VARCHAR(255), userGroupID INT, OUT statusCode INT)
BEGIN
  -- 2: Invalid Username or Password
  -- 3: Invalaid Group ID
  DECLARE userID BIGINT DEFAULT -1;
  DECLARE userGroupIDCheck INT DEFAULT -1;
  DECLARE varSalt, dbPassword, hashedPassword VARCHAR(255);
  DECLARE accountActivated, isActive TINYINT(1) DEFAULT 0;
  
  SET statusCode=0;
  
  SELECT user_id, salt, password, activated, active, user_group_id
  INTO userID, varSalt, dbPassword, accountActivated, isActive, userGroupIDCheck
  FROM users_main 
  WHERE users_main.username=varUsername AND active=1 AND account_closed=0 AND is_disabled=0 AND is_global_view_user=0;
  
  IF (userID = -1) THEN
    SET statusCode = 2;
  ELSEIF (isActive=0) THEN
    SET statusCode = 2;
  ELSE
    SET hashedPassword = UPPER(SHA2(CONCAT(IFNULL(varSalt,''),IFNULL(varPassword,'')),256));
    IF (hashedPassword <> dbPassword) THEN
      SET statusCode = 2;
    END IF;
  END IF;

  IF (userGroupID IS NOT NULL AND userGroupID!=userGroupIDCheck) then
	SET statusCode = 3;
  END IF;

END$$

DELIMITER ;

