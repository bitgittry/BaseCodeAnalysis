DROP function IF EXISTS `PlayerRestrictionIsPlayerRestricted`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `PlayerRestrictionIsPlayerRestricted`(clientID BIGINT, restrictionType VARCHAR(40), checkType VARCHAR(40)) RETURNS bigint(20)
BEGIN
  -- First Version
  -- DECLARE hasRestriction TINYINT(1) DEFAULT 0;
  DECLARE restrictionID BIGINT DEFAULT 0;

  SELECT player_restriction_id INTO restrictionID
  FROM gaming_player_restrictions
  JOIN gaming_player_restriction_types AS restriction_types ON gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id  
  WHERE gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date AND
	(IFNULL(restrictionType,'All')='All' OR restriction_types.name=restrictionType) AND 
	(CASE checkType
      WHEN 'login' THEN restriction_types.disallow_login
	  WHEN 'transfers' THEN restriction_types.disallow_transfers
	  WHEN 'deposits' THEN restriction_types.disallow_transfers OR restriction_types.disallow_deposits
	  WHEN 'withdrawals' THEN restriction_types.disallow_transfers OR restriction_types.disallow_withdrawals
	  WHEN 'play' THEN restriction_types.disallow_play
	  WHEN 'pin' THEN restriction_types.disallow_pin
	  ELSE 1
	END) LIMIT 1;

  RETURN restrictionID;

END$$

DELIMITER ;