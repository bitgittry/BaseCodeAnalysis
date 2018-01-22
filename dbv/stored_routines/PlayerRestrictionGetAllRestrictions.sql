DROP procedure IF EXISTS `PlayerRestrictionGetAllRestrictions`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerRestrictionGetAllRestrictions`(clientID BIGINT, playerRestrictionID BIGINT)
BEGIN
  -- IF playerRestrictionID is not 0 always return the record
  -- Added removal username and removal reason
  SELECT player_restriction_id, gaming_player_restrictions.player_restriction_type_id, gaming_player_restriction_types.name AS player_restriction_type_name, gaming_player_restriction_types.display_name AS player_restriction_type, request_date, is_indefinitely, restrict_num_minutes, 
    restrict_from_date, restrict_until_date, gaming_license_type.name AS license_type, gaming_player_restrictions.is_active, gaming_player_restrictions.reason, users_main.username, gaming_player_restrictions.removal_reason, removal_users_main.username AS removal_username
  FROM gaming_player_restrictions
  JOIN gaming_player_restriction_types ON gaming_player_restrictions.player_restriction_type_id=gaming_player_restriction_types.player_restriction_type_id
  LEFT JOIN gaming_license_type ON gaming_player_restrictions.license_type_id=gaming_license_type.license_type_id
  LEFT JOIN users_main ON gaming_player_restrictions.user_id=users_main.user_id
  LEFT JOIN users_main AS removal_users_main ON gaming_player_restrictions.removal_user_id=removal_users_main.user_id
  WHERE (clientID=0 OR client_id=clientID) AND ((playerRestrictionID=0 AND gaming_player_restrictions.is_active=1 AND gaming_player_restrictions.restrict_until_date>NOW()) OR player_restriction_id=playerRestrictionID) AND gaming_player_restriction_types.is_active=1;
END$$

DELIMITER ;

