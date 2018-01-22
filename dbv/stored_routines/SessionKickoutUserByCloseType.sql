DROP procedure IF EXISTS `SessionKickoutUserByCloseType`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SessionKickoutUserByCloseType`(sessionID BIGINT, userID BIGINT, closeType VARCHAR(80))
BEGIN
   
  UPDATE sessions_main 
  SET 
    date_closed=NOW(), status_code=2, 
    date_expiry=SUBTIME(NOW(), '00:00:01'), session_close_type_id=(SELECT session_close_type_id FROM sessions_close_types WHERE name=IFNULL(closeType, 'UserKickout')) ,
    user_update_session_id=sessionID
  WHERE user_id=userID AND extra_id IS NULL AND status_code=1;
  
END$$

DELIMITER ;

