DROP procedure IF EXISTS `SportsBookGetPlayerFavourites`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SportsBookGetPlayerFavourites`(clientID BIGINT(20))
BEGIN
 
SELECT pref.sb_default_bet_stake, pref.betslip_notification, pref.keep_betslip_selections, btypes.name as 'betslip_type', opt.name as 'auto_accept_odds_option'
 FROM gaming_sb_client_preferences pref
	JOIN gaming_sb_betslip_types btypes ON btypes.sb_betslip_type_id = pref.sb_betslip_type_id
	JOIN gaming_sb_auto_accept_odds_options opt ON opt.sb_auto_accept_odds_option_id = pref.sb_auto_accept_odds_option_id
WHERE pref.client_id = clientID;

SELECT * FROM gaming_sb_client_favourite_bet_stakes WHERE client_id = clientID;

SELECT sports.sb_sport_id, sports.ext_sport_id, sports.name, ggm.name as manuf_name FROM gaming_sb_client_favourite_entities entities 
	JOIN gaming_sb_entity_types types ON types.sb_entity_type_id = entities.sb_entity_type_id AND types.name = 'Sport'
	JOIN gaming_sb_sports sports ON sports.sb_sport_id = entities.entity_id
	JOIN gaming_game_manufacturers ggm ON sports.game_manufacturer_id = ggm.game_manufacturer_id
 WHERE entities.client_id = clientID;

SELECT groups.sb_group_id, groups.name, groups.ext_group_id, ggm.name as manuf_name  FROM gaming_sb_client_favourite_entities entities 
	JOIN gaming_sb_entity_types types ON types.sb_entity_type_id = entities.sb_entity_type_id AND types.name = 'Group'
	JOIN gaming_sb_groups groups ON groups.sb_group_id = entities.entity_id
	JOIN gaming_game_manufacturers ggm ON groups.game_manufacturer_id = ggm.game_manufacturer_id
 WHERE entities.client_id = clientID;

SELECT teams.sb_team_id, teams.name AS team_name, teams.ext_team_id, ggm.name as manuf_name , sports.name AS sport_name FROM gaming_sb_client_favourite_entities entities 
	JOIN gaming_sb_entity_types types ON types.sb_entity_type_id = entities.sb_entity_type_id AND types.name = 'Team'
	JOIN gaming_sb_teams teams ON teams.sb_team_id = entities.entity_id
	JOIN gaming_sb_sports sports ON sports.sb_sport_id = teams.sb_sport_id
	JOIN gaming_game_manufacturers ggm ON teams.game_manufacturer_id = ggm.game_manufacturer_id
 WHERE entities.client_id = clientID;

END$$

DELIMITER ;

