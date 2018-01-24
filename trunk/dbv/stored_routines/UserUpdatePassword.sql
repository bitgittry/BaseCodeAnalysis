DROP procedure IF EXISTS `UserUpdatePassword`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `UserUpdatePassword`(userID BIGINT, varPassword VARCHAR(250))
BEGIN

  -- Inserting in gaming_clients_password_changes if password was changed
  -- Updating num_password_changes if password was changed  
  -- Always updating last_password_change_date

  DECLARE HashTypeID INT;
  DECLARE curPassword VARCHAR(255);
  DECLARE numPasswordChanges INT DEFAULT 0;
 
  SELECT password INTO curPassword FROM users_main WHERE user_id=userID;

  UPDATE users_main 
  SET  password=IFNULL(varPassword, password), 
	   last_password_change_date=IF(varPassword IS NOT NULL, NOW(), last_password_change_date), 
	   num_password_changes=IF(varPassword IS NOT NULL AND varPassword!=curPassword, num_password_changes+1, num_password_changes),
	   require_password_change=0
  WHERE user_id=userID;

  UPDATE users_login_attempts_totals
  SET last_consecutive_bad=0, temporary_locking_bad_attempts=0
  WHERE user_id=userID; 

  IF (varPassword IS NOT NULL AND varPassword!=curPassword) THEN
	  INSERT INTO users_password_changes (user_id, change_num, hashed_password, salt)
	  SELECT user_id, num_password_changes, password, salt
	  FROM users_main
	  WHERE user_id=userID;
  END IF;
  
END$$

DELIMITER ;

