DROP function IF EXISTS `PlayerSelectionIsPlayerInSelectionWithExcludeDynamicFilter`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `PlayerSelectionIsPlayerInSelectionWithExcludeDynamicFilter`(
  playerSelectionID BIGINT, clientStatID BIGINT, excludeDynamicFilters TINYINT(1), ignoreOtherFiltersThanDynamicFilters TINYINT(1)) RETURNS tinyint(1)
    READS SQL DATA
BEGIN
  -- added parameters: excludeDynamicFilters, ignoreOtherFiltersThanDynamicFilters	
  -- Optimized further: this should be slower than 10 milliseconds
  -- Update child selections to get from the selection cache
  -- Forcing indexes 
  -- Split into separate queries     
 
  /* Parameters:
       1. excludeDynamicFilters: already computerd
       2. ignoreOtherFiltersThanDynamicFilters:
   */
 
  DECLARE isPlayerInSelection, isPlayerInSelectionTemp, isPlayerInSelectionSpecialFilter, bonusSeeker, bonusDontWant TINYINT(1) DEFAULT 0;
  DECLARE clientID BIGINT DEFAULT -1;  
  DECLARE numDynamicFilters, numSpecialFilters INT DEFAULT 0;

  SELECT open_to_all, selected_players, group_selection, player_selection, client_segment, player_filter, dynamic_filter, 
	dynamic_filter_on_selection, gaming_player_filters.player_filter_id, exclude_bonus_seeker, exclude_bonus_dont_want, 
    client_segments_num_match, dynamic_filters_num_match
  INTO @openToAllFlag, @selectedPlayersFlag, @groupSelectionFlag, @playerSelectionFlag, @clientSegmentFlag, @playerFilterFlag, @dynamicFilter, 
	@dynamic_filter_on_selection, @playerFilterID, @excludeBonusSeeker, @excludeBonusDontWant, 
    @clientSegmentsNumMatch, @dynamicFiltersNumMatch
  FROM gaming_player_selections 
  LEFT JOIN gaming_player_filters ON 
    gaming_player_selections.player_selection_id=playerSelectionID AND 
    gaming_player_selections.player_selection_id=gaming_player_filters.player_selection_id      
  WHERE gaming_player_selections.player_selection_id=playerSelectionID; 
  
  SELECT gaming_client_stats.client_id, IF(gaming_clients.bonus_seeker OR gaming_fraud_rule_client_settings.bonus_seeker, 1, 0), gaming_clients.bonus_dont_want 
  INTO clientID, bonusSeeker, bonusDontWant
  FROM gaming_client_stats 
  JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_client_stats.client_id
  WHERE gaming_client_stats.client_stat_id=clientStatID;

  IF ((@excludeBonusSeeker=1 AND bonusSeeker=1) OR (@excludeBonusDontWant=1 AND bonusDontWant=1)) THEN
	RETURN 0;
  END IF;
  
  
  -- Check for special filters
  IF (@dynamicFilter=1) THEN
	  
      SELECT COUNT(*), SUM(IF(filters.is_special, 1, 0))
      INTO numDynamicFilters, numSpecialFilters
      FROM gaming_player_selections_dynamic_filters AS gpsdf
      STRAIGHT_JOIN gaming_players_dynamic_filters AS filters ON filters.dynamic_filter_id=gpsdf.dynamic_filter_id
      WHERE gpsdf.player_selection_id=playerSelectionID;

	  -- Player must be in all dynamic filters if there is at least one special filter and number of match is greater than 1
	  IF (numSpecialFilters>0 AND @dynamicFiltersNumMatch>1) THEN
		SET @dynamicFiltersNumMatch=numDynamicFilters-numSpecialFilters;
      END IF;
      
  END IF;

  SET ignoreOtherFiltersThanDynamicFilters=ignoreOtherFiltersThanDynamicFilters=1 
	AND @dynamic_filter_on_selection=1 AND @dynamicFilter=1 AND numSpecialFilters=0;
  
  SET excludeDynamicFilters=excludeDynamicFilters=1 OR @dynamicFilter=0;

  IF (ignoreOtherFiltersThanDynamicFilters) THEN

	  -- inclusions
	  SELECT 1 INTO isPlayerInSelectionTemp
	  FROM gaming_player_selections_dynamic_filters AS gpsdf
	  JOIN gaming_player_selections_dynamic_filter_players AS dyn_selected_players FORCE INDEX (PRIMARY) ON 
		(gpsdf.player_selection_id=playerSelectionID) AND
		(gpsdf.player_selection_dynamic_filter_id = dyn_selected_players.player_selection_dynamic_filter_id AND dyn_selected_players.client_stat_id=clientStatID)
	  WHERE excludeDynamicFilters=0 
	  GROUP BY dyn_selected_players.client_stat_id  
	  HAVING COUNT(*) >= @dynamicFiltersNumMatch;

  ELSE
	  -- Dynamic Filters: Continue with other filters

      -- inclusions

      IF (isPlayerInSelectionTemp=0 AND @openToAllFlag=1) THEN
		SET isPlayerInSelectionTemp=1;
	  END IF;

	  IF (isPlayerInSelectionTemp=0 AND @selectedPlayersFlag=1) THEN
		  SELECT 1 INTO isPlayerInSelectionTemp
		  FROM gaming_player_selections_selected_players AS selected_players FORCE INDEX (PRIMARY)
		  WHERE player_selection_id=playerSelectionID AND client_stat_id=clientStatID AND include_flag=1; 
      END IF;

	  IF (isPlayerInSelectionTemp=0 AND @groupSelectionFlag=1) THEN
		  SELECT 1 INTO isPlayerInSelectionTemp
		  FROM gaming_player_selections_player_groups AS player_groups
		  JOIN gaming_player_groups_client_stats AS selected_players FORCE INDEX (PRIMARY) ON 
			(player_groups.player_selection_id=playerSelectionID AND player_groups.include_flag=1) 
			AND player_groups.player_group_id=selected_players.player_group_id AND selected_players.client_stat_id=clientStatID;
      END IF;

	  IF (isPlayerInSelectionTemp=0 AND @playerSelectionFlag=1) THEN
		  SELECT 1 INTO isPlayerInSelectionTemp
		  FROM gaming_player_selections_child_selections AS child_selections 
		  JOIN gaming_player_selections_player_cache AS selected_players FORCE INDEX (PRIMARY) ON 
			child_selections.player_selection_id=playerSelectionID AND child_selections.include_flag=1 AND
			(child_selections.child_player_selection_id=selected_players.player_selection_id AND selected_players.client_stat_id=clientStatID) AND selected_players.player_in_selection=1;
      END IF;

	  IF (isPlayerInSelectionTemp=0 AND @clientSegmentFlag=1) THEN
		  SELECT 1 INTO isPlayerInSelectionTemp
		  FROM gaming_player_selections_client_segments AS client_segments
		  JOIN gaming_client_segments_players AS selected_players FORCE INDEX (segment_client_current) ON 
			(client_segments.player_selection_id=playerSelectionID AND client_segments.include_flag=1)  
			AND (client_segments.client_segment_id=selected_players.client_segment_id AND selected_players.client_id=clientID AND selected_players.is_current)
		  JOIN gaming_client_stats ON (gaming_client_stats.client_id=selected_players.client_id AND gaming_client_stats.is_active=1) 
		  GROUP BY gaming_client_stats.client_stat_id  
		  HAVING COUNT(*) >= @clientSegmentsNumMatch;
      END IF;
      
      IF (isPlayerInSelectionTemp=0 AND @playerFilterFlag=1) THEN
		  SELECT 1 INTO isPlayerInSelectionTemp
		  FROM gaming_player_filters FORCE INDEX (PRIMARY)
		  JOIN gaming_client_stats FORCE INDEX (PRIMARY) ON gaming_player_filters.player_filter_id=@playerFilterID AND gaming_client_stats.client_stat_id=clientStatID
		  JOIN gaming_clients ON 
			gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active=1 AND
			(gaming_player_filters.gender='B' OR gaming_clients.gender=gaming_player_filters.gender) AND
			(PlayerGetAge(gaming_clients.dob) BETWEEN gaming_player_filters.age_range_start AND gaming_player_filters.age_range_end) 
		  JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary=1 
		  LEFT JOIN gaming_player_filters_countries ON gaming_player_filters.countries_include=1 AND 
			gaming_player_filters_countries.player_filter_id=gaming_player_filters.player_filter_id AND clients_locations.country_id=gaming_player_filters_countries.country_id
		  LEFT JOIN gaming_player_filters_currencies ON gaming_player_filters.currencies_include=1 AND
			gaming_player_filters_currencies.player_filter_id=gaming_player_filters.player_filter_id AND gaming_client_stats.currency_id=gaming_player_filters_currencies.currency_id
		  LEFT JOIN gaming_player_filters_affiliates ON gaming_player_filters.affiliates_include=1 AND
			gaming_player_filters_affiliates.player_filter_id=gaming_player_filters.player_filter_id AND gaming_clients.affiliate_id=gaming_player_filters_affiliates.affiliate_id
		  LEFT JOIN gaming_player_filters_bonus_coupons ON gaming_player_filters.bonus_coupons_include=1 AND
			gaming_player_filters_bonus_coupons.player_filter_id=gaming_player_filters.player_filter_id AND gaming_clients.bonus_coupon_id=gaming_player_filters_bonus_coupons.bonus_coupon_id
		  WHERE 
			@playerFilterFlag AND
			
			(gaming_player_filters.countries_include=0 OR gaming_player_filters_countries.player_filter_id IS NOT NULL) AND 
			(gaming_player_filters.countries_exclude=0 OR NOT EXISTS (SELECT country_id FROM gaming_player_filters_countries AS countries_exclude WHERE countries_exclude.player_filter_id=gaming_player_filters.player_filter_id AND clients_locations.country_id=countries_exclude.country_id)) AND
			(gaming_player_filters.currencies_include=0 OR gaming_player_filters_currencies.player_filter_id IS NOT NULL) AND 
			(gaming_player_filters.currencies_exclude=0 OR NOT EXISTS (SELECT currency_id FROM gaming_player_filters_currencies AS currencies_exclude WHERE currencies_exclude.player_filter_id=gaming_player_filters.player_filter_id AND gaming_client_stats.currency_id=currencies_exclude.currency_id)) AND 
			(gaming_player_filters.affiliates_include=0 OR gaming_player_filters_affiliates.player_filter_id IS NOT NULL) AND 
			(gaming_player_filters.affiliates_exclude=0 OR NOT EXISTS (SELECT affiliate_id FROM gaming_player_filters_affiliates AS affiliates_exclude WHERE affiliates_exclude.player_filter_id=gaming_player_filters.player_filter_id AND gaming_clients.affiliate_id=affiliates_exclude.affiliate_id)) AND
			(gaming_player_filters.bonus_coupons_include=0 OR gaming_player_filters_bonus_coupons.player_filter_id IS NOT NULL) AND 
			(gaming_player_filters.bonus_coupons_exclude=0 OR NOT EXISTS (SELECT bonus_coupon_id FROM gaming_player_filters_bonus_coupons AS bonus_coupons_exclude WHERE bonus_coupons_exclude.player_filter_id=gaming_player_filters.player_filter_id AND gaming_clients.bonus_coupon_id=bonus_coupons_exclude.bonus_coupon_id)); 
	  END IF;

-- numSpecialFilters
-- dynamic_filter_on_selection

	  IF (@dynamicFilter=1 AND 
			(isPlayerInSelectionTemp=0 OR (numSpecialFilters>0 AND @dynamic_filter_on_selection)) AND -- If Player is already selected we usually skip the others but if dynamic filter needs to execute on selection we may need to exclude player
            (@dynamic_filter_on_selection=0 OR isPlayerInSelectionTemp) -- If need to execude dynamic filter on players selected by above selection but the player was not selected then don't continue
		 ) THEN
		  
          SELECT 1 INTO isPlayerInSelectionTemp
		  FROM gaming_player_selections_dynamic_filters AS gpsdf
		  JOIN gaming_player_selections_dynamic_filter_players AS dyn_selected_players FORCE INDEX (PRIMARY) ON 
			gpsdf.player_selection_id=playerSelectionID AND
			(gpsdf.player_selection_dynamic_filter_id = dyn_selected_players.player_selection_dynamic_filter_id AND dyn_selected_players.client_stat_id=clientStatID)
		  WHERE excludeDynamicFilters=0 
		  GROUP BY dyn_selected_players.client_stat_id  
		  HAVING COUNT(*) >= @dynamicFiltersNumMatch;
          
          IF (numSpecialFilters>0) THEN

			  -- If it is at least @dynamicFiltersNumMatch 1
			  IF (
					(@dynamicFiltersNumMatch=1 AND isPlayerInSelectionTemp=0) OR 
					(@dynamicFiltersNumMatch>1 AND isPlayerInSelectionTemp)
			  ) THEN
			 
                SELECT IF(@dynamicFiltersNumMatch=1, COUNT(*)>=1, COUNT(*)=numSpecialFilters) 
                INTO isPlayerInSelectionSpecialFilter
                FROM
                (
					SELECT filters.`name`, 
						MAX(IF(vars.var_reference='[A]', ps_vars.value, NULL)) AS varA,
						MAX(IF(vars.var_reference='[B]', ps_vars.value, NULL)) AS varB
					FROM gaming_player_selections_dynamic_filters AS gpsdf
					STRAIGHT_JOIN gaming_players_dynamic_filters AS filters ON filters.dynamic_filter_id=gpsdf.dynamic_filter_id
					STRAIGHT_JOIN gaming_player_selections_dynamic_filter_vars AS ps_vars ON gpsdf.player_selection_dynamic_filter_id=ps_vars.player_selection_dynamic_filter_id
					STRAIGHT_JOIN gaming_players_dynamic_filter_vars AS vars ON vars.dynamic_filter_var_id=ps_vars.dynamic_filter_var_id
					WHERE gpsdf.player_selection_id=playerSelectionID AND filters.is_special
					GROUP BY gpsdf.player_selection_dynamic_filter_id
				) AS dynamic_filters
                STRAIGHT_JOIN gaming_clients ON gaming_clients.client_id=clientID
                STRAIGHT_JOIN gaming_client_registrations ON gaming_clients.client_id=gaming_client_registrations.client_id
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
				GROUP BY gaming_clients.client_id;
				
                -- If the player was selected previously and the number of dynamic filters to match is greater than 1 and all special filters must match as well 
                IF (isPlayerInSelectionSpecialFilter=0 AND isPlayerInSelectionTemp=1 
						AND @dynamicFiltersNumMatch>1 AND @dynamic_filter_on_selection=1) THEN
					
                    SET isPlayerInSelectionTemp=0;
                END IF;
                 
			  END IF;		
          
		  END IF; -- numSpecialFilters>0
          
      END IF;

  END IF;

    -- exclusions
	
      IF (isPlayerInSelectionTemp=1 AND @selectedPlayersFlag=1) THEN
		SELECT 0 INTO isPlayerInSelectionTemp
		FROM gaming_player_selections_selected_players AS selected_players FORCE INDEX (PRIMARY)
		WHERE player_selection_id=playerSelectionID AND exclude_flag=1 AND client_stat_id=clientStatID; 
      END IF;

	  IF (isPlayerInSelectionTemp=1 AND @groupSelectionFlag=1) THEN
		SELECT 0 INTO isPlayerInSelectionTemp 
		FROM gaming_player_selections_player_groups AS player_groups
		JOIN gaming_player_groups_client_stats AS selected_players FORCE INDEX (PRIMARY)ON 
		  player_groups.player_selection_id=playerSelectionID AND player_groups.exclude_flag=1 AND player_groups.player_group_id=selected_players.player_group_id 
		WHERE selected_players.client_stat_id=clientStatID; 
      END IF;

	  IF (isPlayerInSelectionTemp=1 AND @playerSelectionFlag=1) THEN
		SELECT 0 INTO isPlayerInSelectionTemp
		FROM gaming_player_selections_child_selections AS child_selections 
		JOIN gaming_player_selections_player_cache AS selected_players FORCE INDEX (PRIMARY) ON 
		  child_selections.player_selection_id=playerSelectionID AND child_selections.exclude_flag=1 AND
		  (child_selections.child_player_selection_id=selected_players.player_selection_id AND selected_players.client_stat_id=clientStatID) AND selected_players.player_in_selection=1
		WHERE selected_players.client_stat_id=clientStatID; 
      END IF;

	  IF (isPlayerInSelectionTemp=1 AND @clientSegmentFlag=1) THEN
		  SELECT 0 INTO isPlayerInSelectionTemp 
		  FROM gaming_player_selections_client_segments AS client_segments
		  JOIN gaming_client_segments_players AS selected_players FORCE INDEX (segment_client_current) ON 
			client_segments.player_selection_id=playerSelectionID AND client_segments.exclude_flag=1 
			AND (client_segments.client_segment_id=selected_players.client_segment_id AND selected_players.client_id=clientID AND selected_players.is_current)
		  JOIN gaming_client_stats ON selected_players.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active=1
		  WHERE gaming_client_stats.client_stat_id=clientStatID
		  GROUP BY gaming_client_stats.client_stat_id  
		  HAVING COUNT(*) >= @clientSegmentsNumMatch;
      END IF;

	SET isPlayerInSelection=isPlayerInSelectionTemp;

	-- check expiry date is enable on player selection
	-- If true and player in selection, check if exists record on cache and check if expiry date is less than now(), if is less return 0, otherwise 1
	SET @expiryTimeEnable=(select player_minutes_to_expire from gaming_player_selections where player_selection_id = playerSelectionID);
	IF (@expiryTimeEnable IS NOT NULL AND @expiryTimeEnable> 0 AND isPlayerInSelection = 1) THEN
		SET @expiry_date= (SELECT expiry_date FROM gaming_player_selections_player_cache WHERE player_selection_id = playerSelectionID AND client_stat_id = clientStatID);
		SET isPlayerInSelection = IF(@expiry_date IS NOT NULL AND @expiry_date< NOW(), 0, 1);
		-- IF there is no record on cache, we assume that player has just joined the selection
	END IF;

	RETURN isPlayerInSelection;

END$$

DELIMITER ;

