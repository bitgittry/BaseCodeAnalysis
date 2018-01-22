DROP procedure IF EXISTS `FraudMatchClientName`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudMatchClientName`(clientID BIGINT, OUT similarCount BIGINT)
BEGIN
  -- capitalized input parameters types
  -- Super Optimized
  -- Frank fix :: SUP-6049 with NULLIF 
  -- INBIGLW-730 :: Input sanitized so that wordbreak characters are omitted for the MATCH operator not to give error.
    
  DECLARE prefixLength INT DEFAULT 2;
  DECLARE levenstainMaxLength INT DEFAULT 96;
  
  DECLARE fullTextFilter VARCHAR(64) DEFAULT NULL;
  DECLARE levenstainText VARCHAR(127) DEFAULT NULL;
  
  DECLARE currentFraudRuleId BIGINT; 
  DECLARE currentSimilarityThreshold DECIMAL(18, 5);
  
  SELECT TRIM(CONCAT_WS('* ', 
			NULLIF(SUBSTR(IF(TRIM(`name`) = '', NULL, SanitizeFullTextSearchInput(TRIM(`name`), '')), 1, prefixLength), ''), 
			NULLIF(SUBSTR(IF(TRIM(`middle_name`) = '', NULL, SanitizeFullTextSearchInput(TRIM(`middle_name`), '')), 1, prefixLength), ''), 
			NULLIF(SUBSTR(IF(TRIM(`surname`) = '', NULL, SanitizeFullTextSearchInput(TRIM(`surname`), '')), 1, prefixLength), ''), 
			NULLIF(SUBSTR(IF(TRIM(`sec_surname`) = '', NULL, SanitizeFullTextSearchInput(TRIM(`sec_surname`), '')), 1, prefixLength), ''), '')
		 ),
         UPPER(RIGHT(CONCAT_WS(' ',
			NULLIF(IF(TRIM(`name`) = '', NULL, SanitizeFullTextSearchInput(TRIM(`name`), '')), ''), 
			NULLIF(IF(TRIM(`middle_name`) = '', NULL, SanitizeFullTextSearchInput(TRIM(`middle_name`), '')), ''), 
			NULLIF(IF(TRIM(`surname`) = '', NULL, SanitizeFullTextSearchInput(TRIM(`surname`), '')), ''), 
			NULLIF(IF(TRIM(`sec_surname`) = '', NULL, SanitizeFullTextSearchInput(TRIM(`sec_surname`), '')), '')
		 ), levenstainMaxLength)) 
         INTO fullTextFilter, levenstainText
  FROM gaming_clients 
  WHERE client_id=clientID;

  SELECT fraud_rule_id, similarity_threshold INTO currentFraudRuleId, currentSimilarityThreshold 
  FROM gaming_fraud_rules gfr 
  WHERE (gfr.`name` = 'similar_name' AND gfr.is_active = 1);
  
  SET similarCount = 0;

  IF currentFraudRuleId IS NOT NULL THEN
    
    DELETE FROM gaming_fraud_similarity_thresholds WHERE fraud_rule_id=currentFraudRuleId AND client_id_1=clientID;
        
	INSERT INTO gaming_fraud_similarity_thresholds (fraud_rule_id, client_id_1, client_id_2, similarity_threshold)
	SELECT currentFraudRuleId, clientID, x.client_id, ROUND(x.ratio, 4) 
    FROM (
		SELECT gc.client_id, LevenshteinRatio(
			levenstainText, 
            UPPER(RIGHT(CONCAT_WS(' ',
			IF(TRIM(gc.`name`) = '', NULL, TRIM(gc.`name`)), 
			IF(TRIM(gc.`middle_name`) = '', NULL, TRIM(gc.`middle_name`)), 
			IF(TRIM(gc.`surname`) = '', NULL, TRIM(gc.`surname`)), 
			IF(TRIM(gc.`sec_surname`) = '', NULL, TRIM(gc.`sec_surname`))
		 ), levenstainMaxLength)) 
		) AS ratio 
		FROM gaming_clients gc FORCE INDEX (fraud_similar_name)
		LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gc.client_id
		WHERE 
		   (MATCH (`name`, `middle_name`, `surname`,  `sec_surname`) AGAINST (fullTextFilter IN BOOLEAN MODE)) AND 
			((gaming_fraud_rule_client_settings.block_account = 0 OR 
				gaming_fraud_rule_client_settings.block_account = NULL) AND gc.is_account_closed=0) AND 
                gc.client_id!=clientID 
				AND NOT EXISTS 
                (
					SELECT gfst.client_id_1 FROM gaming_fraud_similarity_thresholds gfst 
					WHERE gfst.fraud_rule_id = currentFraudRuleId AND gfst.client_id_1 = clientID AND gfst.client_id_2 = gc.client_id
				)              
		LIMIT 25
	) AS x 
	WHERE x.ratio > currentSimilarityThreshold
	ON DUPLICATE KEY UPDATE similarity_threshold=VALUES(similarity_threshold);
    
    SELECT COUNT(*) INTO similarCount FROM gaming_fraud_similarity_thresholds WHERE fraud_rule_id = currentFraudRuleId AND client_id_1 = clientID;
  END IF;
   
END$$

DELIMITER ;

