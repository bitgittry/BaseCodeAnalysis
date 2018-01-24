DROP function IF EXISTS `DynamicFilterGetQueryString`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `DynamicFilterGetQueryString`(playerSelectionDynamicFilterID BIGINT) RETURNS text CHARSET utf8
BEGIN
  -- optimized to get filter for player
  -- optimized on dynamicFilterOnSelection=1  by getting from PlayerSelectionIsPlayerInSelectionWithExcludeDynamicFilter if it is ran for player 
  -- optimized on dynamicFilterOnSelection=0  to get the player from the gaming_client_stats where client_stat_id=@clientStatID
  -- optimized further by adding a parameter to PlayerSelectionIsPlayerInSelectionWithExcludeDynamicFilter: ignoreOtherFiltersThanDynamicFilters
  -- Caching dynamic filter 

  DECLARE sqlData, cachedSqlData TEXT DEFAULT NULL;
  DECLARE defaultTableName VARCHAR(80) DEFAULT NULL;
  DECLARE dynamicFilterOnSelection TINYINT(1) DEFAULT 0;
  DECLARE playerSelectionDynamicFilterIDCheck, playerSelectionID BIGINT DEFAULT -1;
  DECLARE playerSelectionAllQueryString TEXT DEFAULT NULL;
  
  SET @hasPlayer=(@clientStatID IS NOT NULL AND @clientStatID!=0);
 
  SELECT gpsdf.player_selection_dynamic_filter_id, IF(@hasPlayer AND sql_data_player IS NOT NULL,sql_data_player, sql_data), default_table_name, 
	gps.dynamic_filter_on_selection, gps.player_selection_id, gpsdf.dynamic_filter_query_for_player
  INTO playerSelectionDynamicFilterIDCheck, sqlData, defaultTableName, 
	dynamicFilterOnSelection, playerSelectionID, cachedSqlData
  FROM gaming_player_selections_dynamic_filters gpsdf FORCE INDEX (PRIMARY)
  STRAIGHT_JOIN gaming_players_dynamic_filters gpdf ON (gpsdf.dynamic_filter_id = gpdf.dynamic_filter_id)
  STRAIGHT_JOIN gaming_player_selections gps ON (gpsdf.player_selection_id = gps.player_selection_id)
  WHERE gpsdf.player_selection_dynamic_filter_id=playerSelectionDynamicFilterID;
  
  IF (cachedSqlData IS NOT NULL AND @hasPlayer) THEN
	RETURN cachedSqlData;
  END IF;

  SET @sqlData=sqlData;
  SET @counter=0;
  
  SELECT @sqlData
  INTO sqlData
  FROM
  (
    SELECT @counter:=@counter+1 AS counter, @sqlData:=REPLACE(@sqlData, gpdfv.var_reference, IF (gpsdfv.`value` IS NULL, gpdfv.default_value, REPLACE(gpsdfv.`value`, '|', ','))) AS sql_data
    FROM gaming_player_selections_dynamic_filters gpsdf
    JOIN gaming_players_dynamic_filter_vars gpdfv ON (gpsdf.dynamic_filter_id = gpdfv.dynamic_filter_id)
    LEFT JOIN gaming_player_selections_dynamic_filter_vars gpsdfv ON (gpsdf.player_selection_dynamic_filter_id = gpsdfv.player_selection_dynamic_filter_id AND gpdfv.dynamic_filter_var_id = gpsdfv.dynamic_filter_var_id)
    WHERE gpsdf.player_selection_dynamic_filter_id=playerSelectionDynamicFilterID
  ) AS XX
  ORDER BY counter
  LIMIT 1;

  IF (dynamicFilterOnSelection) THEN
	IF (@hasPlayer) THEN
		SET playerSelectionAllQueryString = 
		'(SELECT gaming_client_stats.client_stat_id, gaming_client_stats.currency_id, gaming_client_stats.client_id, gaming_client_stats.is_active 
		  FROM gaming_client_stats
		  WHERE client_stat_id=@clientStatID AND PlayerSelectionIsPlayerInSelectionWithExcludeDynamicFilter(@playerSelectionID, @clientStatID, 1, 0) ) ';
	ELSE
		SELECT value_text INTO playerSelectionAllQueryString FROM gaming_settings WHERE name='PLAYER_SELECTION_ALL_QUERY_STRING';
	END IF;

    SET sqlData = REPLACE(sqlData, '{current_selection}', playerSelectionAllQueryString);
  ELSE
	IF (@hasPlayer) THEN
		SET sqlData = REPLACE(sqlData, '{current_selection}', 
			' (SELECT gaming_client_stats.client_stat_id, gaming_client_stats.currency_id, gaming_client_stats.client_id, gaming_client_stats.is_active 
			   FROM gaming_client_stats WHERE client_stat_id=@clientStatID) ');
	ELSE
		SET sqlData = REPLACE(sqlData, '{current_selection}', defaultTableName);
	END IF;
  END IF;

  IF (@hasPlayer) THEN
	SET sqlData=CONCAT('INSERT INTO gaming_player_selections_dynamic_filter_players (player_selection_dynamic_filter_id, last_updated_date, client_stat_id) 
		SELECT @playerSelectionDynamicFilterID, @lastUpdatedDate, client_stat_id FROM ( ',sqlData,' ) AS temp_table
        WHERE client_stat_id=@clientStatID 
        ON DUPLICATE KEY UPDATE last_updated_date=@lastUpdatedDate;');
	
	-- If it is -1 then it will be updated when saving player selection by parent SP
	IF (@clientStatID!=-1) THEN
		UPDATE gaming_player_selections_dynamic_filters SET dynamic_filter_query_for_player=sqlData WHERE player_selection_dynamic_filter_id=playerSelectionDynamicFilterID;
	END IF;
  END IF;

  RETURN sqlData;
END$$

DELIMITER ;

