DROP procedure IF EXISTS `GameUpdateAutoFavouriteGames`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameUpdateAutoFavouriteGames`()
BEGIN

  -- Optimized to calculate only for players that had a new game session
  -- Added FAVOURITE_GAMES_AUTO_CHECK_MONTHS setting 
  
  SET @numAuto = 5;
  SELECT value_int INTO @numAuto FROM gaming_settings WHERE name='PORTAL_NUM_FAVOURITE_GAMES_AUTO';
  
  SET @checkMonths = 3;
  SELECT value_int INTO @checkMonths FROM gaming_settings WHERE name='FAVOURITE_GAMES_AUTO_CHECK_MONTHS';
  SET @filterDate=DATE_SUB(NOW(), INTERVAL @checkMonths MONTH);

  SET @lastCheckDate='2010-01-01';
  SELECT date_created INTO @lastCheckDate FROM gaming_client_stats_favourite_games_counter ORDER BY client_stats_favourite_games_counter_id DESC LIMIT 1;

  INSERT INTO gaming_client_stats_favourite_games_counter (date_created) VALUES (NOW());
  SET @clientStatFavouriteGameCounterID = LAST_INSERT_ID();
    
  -- Calculate the new rankings
  SET @ranking=0;
  SET @prevStatID=-1;
  INSERT INTO gaming_client_stats_favourite_games (client_stat_id, operator_game_id, is_player_assigned, is_auto_assigned, ranking, client_stats_favourite_games_counter_id)
  SELECT client_stat_id, operator_game_id, 0, 1, ranking, @clientStatFavouriteGameCounterID
  FROM
  (
    SELECT 
      IF(client_stat_id<>@prevStatID,@ranking:=1,@ranking:=@ranking+1) AS ranking, IF(@ranking=1,@prevStatID:=client_stat_id,@prevStatID:=@prevStatID), 
      client_stat_id, operator_game_id 
    FROM 
    (
      SELECT gaming_game_sessions.client_stat_id, gaming_game_sessions.operator_game_id, SUM(game_session_id) AS num_logins
      FROM gaming_game_sessions
      JOIN (
		SELECT client_stat_id FROM gaming_game_sessions WHERE session_start_date>=@lastCheckDate GROUP BY client_stat_id
	  ) AS XX ON gaming_game_sessions.client_stat_id=gaming_game_sessions.client_stat_id
	  WHERE gaming_game_sessions.session_start_date>=@filterDate
      GROUP BY gaming_game_sessions.client_stat_id, gaming_game_sessions.operator_game_id  
      ORDER BY gaming_game_sessions.client_stat_id, num_logins DESC 
    ) AS XX 
    ORDER BY client_stat_id, ranking  
  ) AS XY 
  WHERE ranking <= @numAuto 
  ON DUPLICATE KEY UPDATE is_auto_assigned=1, ranking=XY.ranking, client_stats_favourite_games_counter_id=@clientStatFavouriteGameCounterID;
  
  -- Delete Auto Games which have not ranked this time
  DELETE gaming_client_stats_favourite_games 
	FROM gaming_client_stats_favourite_games 
	JOIN (
		SELECT client_stat_id FROM gaming_client_stats_favourite_games WHERE client_stats_favourite_games_counter_id=@clientStatFavouriteGameCounterID GROUP BY client_stat_id
	) AS XX ON gaming_client_stats_favourite_games.client_stat_id=XX.client_stat_id
	WHERE is_player_assigned=0 AND client_stats_favourite_games_counter_id!=@clientStatFavouriteGameCounterID;

  -- UPDATE gaming_client_stats_favourite_games SET is_auto_assigned=0, ranking=0 WHERE is_player_assigned=1 AND client_stats_favourite_games_counter_id!=@clientStatFavouriteGameCounterID;
  
  
END$$

DELIMITER ;

