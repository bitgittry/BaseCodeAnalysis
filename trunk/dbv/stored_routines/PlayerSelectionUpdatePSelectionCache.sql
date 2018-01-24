DROP procedure IF EXISTS `PlayerSelectionUpdatePSelectionCache`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerSelectionUpdatePSelectionCache`(
  playerSelectionID BIGINT, fullCacheUpdate TINYINT(1), isTopLevel TINYINT(1), updateDynamicFilter TINYINT(1))
BEGIN
  -- Optimized: player filter may need to be optimized for million of players 
  -- If need to update check than don't do the optimization
  -- Added parameter fullCacheUpdate 
  -- Added parameter isTopLevel: since we can call this call recursively to update parent selections (not only call recursively once)
  -- Added paramter updateDynamicFilter: pass as 0 when calling from DynamicFilterUpdateAllExpired. Also if there was no change to the dynamic filter we don't need up update e.g. adding once player to the selection. 
  -- Added cache history
  -- Added if even if it not top level but it is dynamicFilterOnSelection set to true then re-run dynamic filter
  -- Caching dynamic filter
  -- Removed optimization for a small number of players within the selection
  -- Moved history and updating of parent selection in PlayerSelectionAfterUpdateCacheForPSelection 
  -- Added Special Dynamic Filters

  DECLARE numPlayers BIGINT DEFAULT 0;
  DECLARE cacheUpdated, hasDynamicFilter, dynamicFilterOnSelection TINYINT(1) DEFAULT 0;
  DECLARE historyEnabled TINYINT(1) DEFAULT 0;
  DECLARE systemEndDate DATETIME DEFAULT '3000-01-01';
  DECLARE expiryTime INT(11) UNSIGNED DEFAULT NULL;
  DECLARE numDynamicFilters, numSpecialFilters, dynamicFiltersNumMatchWithoutSpecial INT DEFAULT 0;

  COMMIT;

  SELECT value_bool INTO historyEnabled FROM gaming_settings WHERE `name`='PLAYER_SELECTION_SAVE_CACHE_HISTORY'; 
  SELECT value_date INTO systemEndDate FROM gaming_settings WHERE `name`='SYSTEM_END_DATE';

  SELECT cache_updated, num_players, dynamic_filter, dynamic_filter_on_selection, player_minutes_to_expire
  INTO cacheUpdated, numPlayers, hasDynamicFilter, dynamicFilterOnSelection, expiryTime
  FROM gaming_player_selections 
  WHERE player_selection_id=playerSelectionID;

  -- Cache the dynamic filter for a player
  IF (hasDynamicFilter) THEN

	SET @clientStatID=-1;
	UPDATE gaming_player_selections_dynamic_filters FORCE INDEX (player_selection_id) 
	SET dynamic_filter_query_for_player=DynamicFilterGetQueryString(player_selection_dynamic_filter_id)
	WHERE player_selection_id=playerSelectionID;

  END IF;

  SET @numMonths=3;
  SET @fullCacheUpdate=0;
  SELECT value_int INTO @numMonths FROM gaming_settings WHERE name='PLAYER_SELECTION_CACHE_MONTH_LIMIT' LIMIT 1;
  
  SET @expiryDate = DATE_ADD(NOW(), INTERVAL expiryTime MINUTE);
  SET @updatedDate=NOW();
  SET @updatedDateDynamicFilter=DATE_ADD(@updatedDate, INTERVAL 1 DAY); -- Just a future date
  SET @playerCounter=0;
  SET @loginCheckDate=DATE_SUB(@updatedDate, INTERVAL @numMonths MONTH);
  
    SELECT open_to_all, selected_players, group_selection, player_selection, client_segment, player_filter, dynamic_filter_on_selection, gaming_player_filters.player_filter_id, 
		DATE_SUB(NOW(), INTERVAL gaming_player_filters.age_range_start YEAR), DATE_SUB(NOW(), INTERVAL gaming_player_filters.age_range_end YEAR), 
		exclude_bonus_seeker, exclude_bonus_dont_want, client_segments_num_match, dynamic_filters_num_match, gaming_player_selections.full_cache_updated
	  INTO @openToAllFlag, @selectedPlayersFlag, @groupSelectionFlag, @playerSelectionFlag, @clientSegmentFlag, @playerFilterFlag, @dynamic_filter_on_selection, @playerFilterID,
		@dobStart, @dobEnd, 
		@excludeBonusSeeker, @excludeBonusDontWant, @clientSegmentsNumMatch, @dynamicFiltersNumMatch, @fullCacheUpdate
	  FROM gaming_player_selections 
	  LEFT JOIN gaming_player_filters ON 
		gaming_player_selections.player_selection_id=playerSelectionID AND 
		gaming_player_selections.player_selection_id=gaming_player_filters.player_selection_id      
	  WHERE gaming_player_selections.player_selection_id=playerSelectionID; 
  
  SET dynamicFiltersNumMatchWithoutSpecial=@dynamicFiltersNumMatch;
  SET @dynamicFiltersNumMatchOriginal=@dynamicFiltersNumMatch;
  
  -- Check for special filters
  IF (hasDynamicFilter=1) THEN
	  
      SELECT COUNT(*), SUM(IF(filters.is_special, 1, 0))
      INTO numDynamicFilters, numSpecialFilters
      FROM gaming_player_selections_dynamic_filters AS gpsdf
      STRAIGHT_JOIN gaming_players_dynamic_filters AS filters ON filters.dynamic_filter_id=gpsdf.dynamic_filter_id
      WHERE gpsdf.player_selection_id=playerSelectionID;

	  -- Player must be in all dynamic filters if there is at least one special filter and number of match is greater than 1
	  IF (numSpecialFilters>0 AND @dynamicFiltersNumMatch>1) THEN
		SET dynamicFiltersNumMatchWithoutSpecial=numDynamicFilters-numSpecialFilters; -- @dynamicFiltersNumMatch is actually the number of dyanmic filters to match excluding special filters
      END IF;

  END IF;
  
	  IF (hasDynamicFilter=1 AND @dynamicFiltersNumMatch>0 AND ((updateDynamicFilter=1 AND isTopLevel=1) OR dynamicFilterOnSelection=1)) THEN
		CALL PlayerSelectionDynamicFiltersUpdateAllExpired(playerSelectionID, 1);
	  END IF;
		
	  IF (@dynamic_filter_on_selection=1 AND numSpecialFilters=0) THEN

		  INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, expiry_date, last_updated)
		  SELECT playerSelectionID, CS.client_stat_id, 1, @expiryDate, @updatedDate    
		  FROM (
		  SELECT CS.client_stat_id, @playerCounter:=@playerCounter+1
		  FROM
		  (      
			  SELECT client_stat_id
			  FROM gaming_player_selections_dynamic_filters AS gpsdf
			  JOIN gaming_player_selections_dynamic_filter_players AS dyn_selected_players ON 
				gpsdf.player_selection_id=playerSelectionID AND
				(gpsdf.player_selection_dynamic_filter_id = dyn_selected_players.player_selection_dynamic_filter_id)
			  GROUP BY dyn_selected_players.client_stat_id  
			  HAVING COUNT(*) >= dynamicFiltersNumMatchWithoutSpecial
		  ) AS CS  
		  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=CS.client_stat_id
		  JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id AND gaming_clients.is_account_closed=0
          LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id
		  JOIN gaming_clients_login_attempts_totals ON gaming_clients.client_id=gaming_clients_login_attempts_totals.client_id AND (@fullCacheUpdate OR gaming_clients_login_attempts_totals.last_success>@loginCheckDate)
		  WHERE ((@excludeBonusSeeker=0 OR (gaming_clients.bonus_seeker=0 AND (gaming_fraud_rule_client_settings.bonus_seeker = 0 OR gaming_fraud_rule_client_settings.bonus_seeker = NULL))) AND (@excludeBonusDontWant=0 OR gaming_clients.bonus_dont_want=0) 
		   ) AND (CS.client_stat_id NOT IN ( 
			SELECT client_stat_id
			FROM gaming_player_selections_selected_players AS selected_players
			WHERE player_selection_id=playerSelectionID AND exclude_flag=1  
		  )) AND (@groupSelectionFlag=0 OR CS.client_stat_id NOT IN ( 
			SELECT selected_players.client_stat_id 
			FROM gaming_player_selections_player_groups AS player_groups
			JOIN gaming_player_groups_client_stats AS selected_players ON 
			  player_groups.player_selection_id=playerSelectionID AND player_groups.exclude_flag=1 AND player_groups.player_group_id=selected_players.player_group_id
		  )) AND (@playerSelectionFlag=0 OR CS.client_stat_id NOT IN ( 
			SELECT selected_players.client_stat_id 
			FROM gaming_player_selections_child_selections AS child_selections 
			JOIN gaming_player_selections_player_cache AS selected_players FORCE INDEX (players_in_selection) ON 
			  (child_selections.player_selection_id=playerSelectionID AND child_selections.exclude_flag=1) AND 
			  (child_selections.child_player_selection_id=selected_players.player_selection_id AND selected_players.player_in_selection=1)
		  )) AND (@clientSegmentFlag=0 OR CS.client_stat_id NOT IN ( 
			  SELECT gaming_client_stats.client_stat_id 
			  FROM gaming_player_selections_client_segments AS client_segments
			  JOIN gaming_client_segments_players AS selected_players ON 
				client_segments.player_selection_id=playerSelectionID AND client_segments.exclude_flag=1 AND (client_segments.client_segment_id=selected_players.client_segment_id AND selected_players.is_current)
			  JOIN gaming_client_stats ON selected_players.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active=1
			  GROUP BY gaming_client_stats.client_stat_id  
			  HAVING COUNT(*) >= @clientSegmentsNumMatch
		  )) AND CS.client_stat_id IS NOT NULL
		  ) AS CS
		  ON DUPLICATE KEY UPDATE gaming_player_selections_player_cache.expiry_date=IF(gaming_player_selections_player_cache.player_in_selection=0 AND gaming_player_selections_player_cache.expiry_date IS NULL, @expiryDate, gaming_player_selections_player_cache.expiry_date),
								  gaming_player_selections_player_cache.player_in_selection=IF(VALUES(player_in_selection), IF(gaming_player_selections_player_cache.expiry_date<NOW(),0,1), 0),
								  gaming_player_selections_player_cache.last_updated=@updatedDate;

	  ELSE

		  INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, expiry_date, last_updated)
		  SELECT playerSelectionID, CS.client_stat_id, 1, @expiryDate, IFNULL(selectionDate, @updatedDate)    
		  FROM (
		  SELECT CS.client_stat_id, MAX(CS.selectionDate) AS selectionDate, @playerCounter:=@playerCounter+1
		  FROM
		  ( 
			( 
			  SELECT gaming_client_stats.client_stat_id, NULL AS selectionDate, 1 AS FilterType, 1 AS NumTimes
			  FROM gaming_clients 
			  JOIN gaming_client_stats FORCE INDEX (client_active) ON @openToAllFlag AND 
				gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active=1
			  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id 
			  JOIN gaming_clients_login_attempts_totals ON gaming_clients.client_id=gaming_clients_login_attempts_totals.client_id AND (@fullCacheUpdate OR gaming_clients_login_attempts_totals.last_success>@loginCheckDate)
              WHERE gaming_clients.is_account_closed=0 AND (gaming_fraud_rule_client_settings.block_account = 0 OR gaming_fraud_rule_client_settings.block_account = NULL)              
			) 
			UNION DISTINCT 
			(
			  SELECT client_stat_id, NULL AS selectionDate, 2 AS FilterType, 1 AS NumTimes
			  FROM gaming_player_selections_selected_players AS selected_players
			  WHERE player_selection_id=playerSelectionID AND include_flag=1 
			)
			UNION DISTINCT 
			( 
			  SELECT selected_players.client_stat_id, NULL AS selectionDate, 3 AS FilterType, 1 AS NumTimes 
			  FROM gaming_player_selections_player_groups AS player_groups
			  JOIN gaming_player_groups_client_stats AS selected_players ON 
				@groupSelectionFlag AND player_groups.player_selection_id=playerSelectionID AND player_groups.include_flag=1 AND player_groups.player_group_id=selected_players.player_group_id
			)
			UNION DISTINCT 
			( 
			  SELECT selected_players.client_stat_id, NULL AS selectionDate, 4 AS FilterType, 1 AS NumTimes
			  FROM gaming_player_selections_child_selections AS child_selections 
			  JOIN gaming_player_selections_player_cache AS selected_players FORCE INDEX (players_in_selection) ON 
				@playerSelectionFlag AND (child_selections.player_selection_id=playerSelectionID AND child_selections.include_flag=1) AND 
				(child_selections.child_player_selection_id=selected_players.player_selection_id AND selected_players.player_in_selection=1)
			)
			UNION DISTINCT 
			( 
			  SELECT gaming_client_stats.client_stat_id, NULL AS selectionDate, 5 AS FilterType, 1 AS NumTimes
			  FROM gaming_player_selections_client_segments AS client_segments
			  JOIN gaming_client_segments_players AS selected_players ON 
				@clientSegmentFlag AND client_segments.player_selection_id=playerSelectionID AND client_segments.include_flag=1 AND (client_segments.client_segment_id=selected_players.client_segment_id AND selected_players.is_current)
			  JOIN gaming_client_stats ON selected_players.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active=1
			  GROUP BY gaming_client_stats.client_stat_id  
			  HAVING COUNT(*) >= @clientSegmentsNumMatch
			)
            UNION DISTINCT
            (
			  SELECT client_stat_id, @updatedDateDynamicFilter AS selectionDate, 6 AS FilterType, COUNT(*) AS NumTimes
			  FROM gaming_player_selections_dynamic_filters AS gpsdf 
			  JOIN gaming_player_selections_dynamic_filter_players AS dyn_selected_players ON 
				gpsdf.player_selection_id=playerSelectionID AND 
				(gpsdf.player_selection_dynamic_filter_id = dyn_selected_players.player_selection_dynamic_filter_id)
			  STRAIGHT_JOIN gaming_players_dynamic_filters AS filters ON 
						filters.dynamic_filter_id=gpsdf.dynamic_filter_id AND filters.is_special=0
			  GROUP BY dyn_selected_players.client_stat_id  
			  HAVING COUNT(*) >= dynamicFiltersNumMatchWithoutSpecial
			)
            UNION DISTINCT 
            (
				SELECT gaming_client_stats.client_stat_id, NULL AS selectionDate, 7 AS FilterType, COUNT(*) AS NumTimes
                FROM
                (
					SELECT filters.`name`, 
						MAX(IF(vars.var_reference='[A]', ps_vars.value, NULL)) AS varA,
						MAX(IF(vars.var_reference='[B]', ps_vars.value, NULL)) AS varB
					FROM gaming_player_selections_dynamic_filters AS gpsdf
					STRAIGHT_JOIN gaming_players_dynamic_filters AS filters ON 
						filters.dynamic_filter_id=gpsdf.dynamic_filter_id AND filters.is_special
					STRAIGHT_JOIN gaming_player_selections_dynamic_filter_vars AS ps_vars ON 
						gpsdf.player_selection_dynamic_filter_id=ps_vars.player_selection_dynamic_filter_id
					STRAIGHT_JOIN gaming_players_dynamic_filter_vars AS vars ON 
						vars.dynamic_filter_var_id=ps_vars.dynamic_filter_var_id
					WHERE gpsdf.player_selection_id=playerSelectionID
					GROUP BY gpsdf.player_selection_dynamic_filter_id
				) AS dynamic_filters
                STRAIGHT_JOIN gaming_clients ON numSpecialFilters>0 AND @dynamic_filter_on_selection=0
					AND gaming_clients.is_account_closed=0
                STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_id=gaming_clients.client_id AND gaming_client_stats.is_active
                STRAIGHT_JOIN gaming_client_registrations ON gaming_clients.client_id=gaming_client_registrations.client_id AND gaming_client_registrations.is_current = 1
                LEFT JOIN gaming_kyc_checked_statuses ON gaming_clients.kyc_checked_status_id = gaming_kyc_checked_statuses.kyc_checked_status_id
                WHERE 
					CASE dynamic_filters.`name`
						WHEN 'account_activated' THEN IF(dynamic_filters.varA='1', 1, 0)=gaming_clients.account_activated -- Actual
						WHEN 'kyc_status' THEN INSTR(CONCAT('|', dynamic_filters.varA, '|'), CONCAT('|', gaming_kyc_checked_statuses.status_code, '|'))>0 -- Example N\A
                        WHEN 'registration_state' THEN INSTR(CONCAT('|', dynamic_filters.varA, '|'), CONCAT('|', gaming_client_registrations.client_registration_type_id, '|'))>0 -- Example N\A
                        WHEN 'player_status' THEN INSTR(CONCAT('|', dynamic_filters.varA, '|'), CONCAT('|', gaming_clients.player_status_id, '|'))>0 -- Example N\A
                        WHEN 'closed_account' THEN IF(dynamic_filters.varA='Include', gaming_clients.is_account_closed = 1 OR gaming_clients.is_active = 1, gaming_clients.is_account_closed = 0 AND gaming_clients.is_active = 1) -- Actual
						ELSE 0
                    END
				GROUP BY gaming_client_stats.client_stat_id
                HAVING IF(@dynamicFiltersNumMatchOriginal<=1, COUNT(*)>=1, COUNT(*)=numSpecialFilters) 
            )
			UNION DISTINCT 
			(
			  SELECT client_stat_id, NULL AS selectionDate, 8 AS FilterType, 1 AS NumTimes 
			  FROM gaming_player_filters FORCE INDEX (PRIMARY)
			  LEFT JOIN gaming_player_filters_countries ON gaming_player_filters.countries_include=1 AND gaming_player_filters_countries.player_filter_id=gaming_player_filters.player_filter_id 
			  LEFT JOIN gaming_player_filters_currencies ON gaming_player_filters.currencies_include=1 AND gaming_player_filters_currencies.player_filter_id=gaming_player_filters.player_filter_id 
			  JOIN clients_locations FORCE INDEX (country_id) ON gaming_player_filters.countries_include=0 OR (clients_locations.country_id=gaming_player_filters_countries.country_id AND clients_locations.is_primary=1)
			  JOIN gaming_clients_login_attempts_totals ON clients_locations.client_id=gaming_clients_login_attempts_totals.client_id AND (@fullCacheUpdate OR gaming_clients_login_attempts_totals.last_success>@loginCheckDate)
			  JOIN gaming_client_stats ON (gaming_player_filters.currencies_include=0 OR gaming_client_stats.currency_id=gaming_player_filters_currencies.currency_id) AND clients_locations.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active=1
			  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = clients_locations.client_id 
              JOIN gaming_clients ON 
				gaming_clients.client_id=clients_locations.client_id AND
				(@playerFilterFlag=1 AND gaming_player_filters.player_filter_id=@playerFilterID) 
				AND (gaming_clients.dob BETWEEN @dobEnd AND @dobStart) 
				AND (gaming_player_filters.gender='B' OR gaming_clients.gender=gaming_player_filters.gender)
			  LEFT JOIN gaming_player_filters_affiliates ON gaming_player_filters.affiliates_include=1 AND gaming_player_filters_affiliates.player_filter_id=gaming_player_filters.player_filter_id AND gaming_clients.affiliate_id=gaming_player_filters_affiliates.affiliate_id
			  LEFT JOIN gaming_player_filters_bonus_coupons ON gaming_player_filters.bonus_coupons_include=1 AND gaming_player_filters_bonus_coupons.player_filter_id=gaming_player_filters.player_filter_id AND gaming_clients.bonus_coupon_id=gaming_player_filters_bonus_coupons.bonus_coupon_id
			  WHERE 
                (gaming_clients.is_account_closed=0 AND (gaming_fraud_rule_client_settings.block_account = 0 OR gaming_fraud_rule_client_settings.block_account = NULL)) AND 
				@playerFilterFlag AND gaming_player_filters.player_filter_id=@playerFilterID AND
				-- (gaming_player_filters.countries_include=0 OR gaming_player_filters_countries.player_filter_id IS NOT NULL) AND 
				(gaming_player_filters.countries_exclude=0 OR NOT EXISTS (SELECT country_id FROM gaming_player_filters_countries AS countries_exclude WHERE countries_exclude.player_filter_id=gaming_player_filters.player_filter_id AND clients_locations.country_id=countries_exclude.country_id)) AND
				-- (gaming_player_filters.currencies_include=0 OR gaming_player_filters_currencies.player_filter_id IS NOT NULL) AND 
				(gaming_player_filters.currencies_exclude=0 OR NOT EXISTS (SELECT currency_id FROM gaming_player_filters_currencies AS currencies_exclude WHERE currencies_exclude.player_filter_id=gaming_player_filters.player_filter_id AND gaming_client_stats.currency_id=currencies_exclude.currency_id)) AND 
				(gaming_player_filters.affiliates_include=0 OR gaming_player_filters_affiliates.player_filter_id IS NOT NULL) AND 
				(gaming_player_filters.affiliates_exclude=0 OR NOT EXISTS (SELECT affiliate_id FROM gaming_player_filters_affiliates AS affiliates_exclude WHERE affiliates_exclude.player_filter_id=gaming_player_filters.player_filter_id AND gaming_clients.affiliate_id=affiliates_exclude.affiliate_id)) AND
				(gaming_player_filters.bonus_coupons_include=0 OR gaming_player_filters_bonus_coupons.player_filter_id IS NOT NULL) AND 
				(gaming_player_filters.bonus_coupons_exclude=0 OR NOT EXISTS (SELECT bonus_coupon_id FROM gaming_player_filters_bonus_coupons AS bonus_coupons_exclude WHERE bonus_coupons_exclude.player_filter_id=gaming_player_filters.player_filter_id AND gaming_clients.bonus_coupon_id=bonus_coupons_exclude.bonus_coupon_id))     
                
			) 
			
          ) AS CS  
		  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=CS.client_stat_id
		  JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id AND gaming_clients.is_account_closed=0
          LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id
		  JOIN gaming_clients_login_attempts_totals ON gaming_clients.client_id=gaming_clients_login_attempts_totals.client_id AND (@fullCacheUpdate OR gaming_clients_login_attempts_totals.last_success>@loginCheckDate) -- OR gaming_clients.sign_up_date>@loginCheckDate)
		  WHERE ((@excludeBonusSeeker=0 OR (gaming_clients.bonus_seeker=0 AND (gaming_fraud_rule_client_settings.bonus_seeker = 0 OR gaming_fraud_rule_client_settings.bonus_seeker = NULL))) AND (@excludeBonusDontWant=0 OR gaming_clients.bonus_dont_want=0) 
			   ) AND (CS.client_stat_id NOT IN ( 
				SELECT client_stat_id
				FROM gaming_player_selections_selected_players AS selected_players
				WHERE player_selection_id=playerSelectionID AND exclude_flag=1  
			  )) AND (@groupSelectionFlag=0 OR CS.client_stat_id NOT IN ( 
				SELECT selected_players.client_stat_id 
				FROM gaming_player_selections_player_groups AS player_groups
				JOIN gaming_player_groups_client_stats AS selected_players ON 
				  player_groups.player_selection_id=playerSelectionID AND player_groups.exclude_flag=1 AND player_groups.player_group_id=selected_players.player_group_id
			  )) AND (@playerSelectionFlag=0 OR CS.client_stat_id NOT IN ( 
				SELECT selected_players.client_stat_id 
				FROM gaming_player_selections_child_selections AS child_selections 
				JOIN gaming_player_selections_player_cache AS selected_players FORCE INDEX (players_in_selection) ON 
				  (child_selections.player_selection_id=playerSelectionID AND child_selections.exclude_flag=1) AND 
				  (child_selections.child_player_selection_id=selected_players.player_selection_id AND selected_players.player_in_selection=1)
			  )) AND (@clientSegmentFlag=0 OR CS.client_stat_id NOT IN ( 
				  SELECT gaming_client_stats.client_stat_id 
				  FROM gaming_player_selections_client_segments AS client_segments
				  JOIN gaming_client_segments_players AS selected_players ON 
					client_segments.player_selection_id=playerSelectionID AND client_segments.exclude_flag=1 AND (client_segments.client_segment_id=selected_players.client_segment_id AND selected_players.is_current)
				  JOIN gaming_client_stats ON selected_players.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active=1
				  GROUP BY gaming_client_stats.client_stat_id  
				  HAVING COUNT(*) >= @clientSegmentsNumMatch
			  )
            ) AND CS.client_stat_id IS NOT NULL
            GROUP BY CS.client_stat_id
            HAVING hasDynamicFilter=0 OR SUM(IF(CS.FilterType NOT IN (6,7), CS.NumTimes, 0))>0 OR SUM(IF(CS.FilterType IN (6,7), CS.NumTimes, 0))>=@dynamicFiltersNumMatchOriginal
		  ) AS CS
		  ON DUPLICATE KEY UPDATE 
			gaming_player_selections_player_cache.expiry_date=IF(gaming_player_selections_player_cache.player_in_selection=0 
				AND gaming_player_selections_player_cache.expiry_date IS NULL, @expiryDate, gaming_player_selections_player_cache.expiry_date),
		    gaming_player_selections_player_cache.player_in_selection=IF(VALUES(player_in_selection), IF(gaming_player_selections_player_cache.expiry_date<NOW(),0,1), 0),
		    gaming_player_selections_player_cache.last_updated=GREATEST(VALUES(last_updated), @updatedDate);
            
		  IF (numSpecialFilters>0 AND @dynamic_filter_on_selection=1) THEN
			
            -- Update the players who were selected previously and also match the filters
            -- Thi is because 1. We get the players 2. Run the dynamic filters on the previously selected players e.g. Filter on other filters
            SET @updatedDate=DATE_ADD(@updatedDate, INTERVAL 1 SECOND);
            
            UPDATE gaming_player_selections_player_cache AS gpspc
            LEFT JOIN
            (
				SELECT gaming_client_stats.client_stat_id, SUM(IF(last_updated=@updatedDateDynamicFilter, 1, 0)) AS selectedFromNormalDynamicFilters
                FROM
                (
					SELECT filters.`name`, 
						MAX(IF(vars.var_reference='[A]', ps_vars.value, NULL)) AS varA,
						MAX(IF(vars.var_reference='[B]', ps_vars.value, NULL)) AS varB
					FROM gaming_player_selections_dynamic_filters AS gpsdf
					STRAIGHT_JOIN gaming_players_dynamic_filters AS filters ON 
						filters.dynamic_filter_id=gpsdf.dynamic_filter_id AND filters.is_special
					STRAIGHT_JOIN gaming_player_selections_dynamic_filter_vars AS ps_vars ON 
						gpsdf.player_selection_dynamic_filter_id=ps_vars.player_selection_dynamic_filter_id
					STRAIGHT_JOIN gaming_players_dynamic_filter_vars AS vars ON 
						vars.dynamic_filter_var_id=ps_vars.dynamic_filter_var_id
					WHERE gpsdf.player_selection_id=playerSelectionID
					GROUP BY gpsdf.player_selection_dynamic_filter_id
				) AS dynamic_filters
				STRAIGHT_JOIN gaming_clients ON gaming_clients.is_account_closed=0
                STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_id=gaming_clients.client_id AND gaming_client_stats.is_active
                STRAIGHT_JOIN gaming_client_registrations ON gaming_clients.client_id=gaming_client_registrations.client_id AND gaming_client_registrations.is_current = 1
                LEFT JOIN gaming_kyc_checked_statuses ON gaming_clients.kyc_checked_status_id = gaming_kyc_checked_statuses.kyc_checked_status_id
                WHERE 
					CASE dynamic_filters.`name`
						WHEN 'account_activated' THEN IF(dynamic_filters.varA='1', 1, 0)=gaming_clients.account_activated -- Actual
						WHEN 'kyc_status' THEN INSTR(CONCAT('|', dynamic_filters.varA, '|'), CONCAT('|', gaming_kyc_checked_statuses.status_code, '|'))>0 -- Example N\A
                        WHEN 'registration_state' THEN INSTR(CONCAT('|', dynamic_filters.varA, '|'), CONCAT('|', gaming_client_registrations.client_registration_type_id, '|'))>0 -- Example N\A
                        WHEN 'player_status' THEN INSTR(CONCAT('|', dynamic_filters.varA, '|'), CONCAT('|', gaming_clients.player_status_id, '|'))>0 -- Example N\A
                        WHEN 'closed_account' THEN IF(dynamic_filters.varA='Include', gaming_clients.is_account_closed = 1 OR gaming_clients.is_active = 1, gaming_clients.is_account_closed = 0 AND gaming_clients.is_active = 1) -- Actual
						ELSE 0
                    END
				GROUP BY gaming_client_stats.client_stat_id
                HAVING IF(@dynamicFiltersNumMatchOriginal=1 AND selectedFromNormalDynamicFilters>0, 1,
					IF(@dynamicFiltersNumMatchOriginal<=1, COUNT(*)>=1, COUNT(*)=numSpecialFilters))
            ) AS ActualPlayers ON gpspc.client_stat_id=ActualPlayers.client_stat_id  
            SET 
				gpspc.player_in_selection=IF(ActualPlayers.client_stat_id IS NULL AND gpspc.last_updated<@updatedDate, 0, 1),
				gpspc.last_updated=IF(ActualPlayers.client_stat_id IS NULL, gpspc.last_updated, IF(gpspc.last_updated=@updatedDateDynamicFilter, systemEndDate, @updatedDate))
			WHERE gpspc.player_selection_id=playerSelectionID AND gpspc.player_in_selection=1;  

            IF(@dynamicFiltersNumMatchOriginal != numSpecialFilters AND @dynamicFiltersNumMatch > 1) THEN
              UPDATE gaming_player_selections_player_cache 
              SET player_in_selection=(last_updated = systemEndDate)
              WHERE player_selection_id = playerSelectionID AND player_in_selection = 1;
            END IF;
            
          END IF;
          
	  END IF;

	  UPDATE gaming_player_selections_player_cache 
	  SET player_in_selection=(last_updated>=@updatedDate), last_updated=@updatedDate
	  WHERE player_selection_id=playerSelectionID AND player_in_selection=1 AND last_updated!=@updatedDate; 

	  UPDATE gaming_player_selections_player_cache 
	  SET player_in_selection=0, last_updated=@updatedDate
	  WHERE player_selection_id=playerSelectionID AND player_in_selection=0 AND last_updated>@updatedDate; 

      -- If selection have selected players and child selections we must count all selected players from cache. But why?
	  SELECT COUNT(*) INTO @playerCounter FROM gaming_player_selections_player_cache WHERE player_selection_id=playerSelectionID  AND player_in_selection=1;
      
	  UPDATE gaming_player_selections SET num_players=@playerCounter, cache_updated=1 WHERE player_selection_id=playerSelectionID;

	  CALL PlayerSelectionAfterUpdateCacheForPSelection(playerSelectionID, isTopLevel, @updatedDate); 
 
END$$

DELIMITER ;

