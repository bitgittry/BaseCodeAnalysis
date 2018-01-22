DROP procedure IF EXISTS `FraudMatchClientDetails`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudMatchClientDetails`(clientID BIGINT, OUT similarCount BIGINT)
BEGIN
   
  -- Super Optimized 
  -- Frank fix: SUP-6049 with NULLIF  
 
  DECLARE prefixLength INT DEFAULT 2;
  DECLARE levenstainMaxLength INT DEFAULT 96;
  
  DECLARE fullTextFilter VARCHAR(64) DEFAULT NULL;
  DECLARE levenstainText VARCHAR(127) DEFAULT NULL;
  DECLARE clientDOB DATE;
  
  DECLARE currentFraudRuleId BIGINT;
  DECLARE currentSimilarityThreshold DECIMAL(18, 5);
  
  DECLARE currentEmailWeight, currentDobWeight DECIMAL(18, 5) DEFAULT 0;
  
  SELECT FraudSimilarityWithFullTextIndexReplaceWildChars(CONCAT(SPLIT_EMAIL_IN_WORDS(`email`, prefixLength, '* '), '*')),
         UPPER(RIGHT(CONCAT_WS(' ',
			NULLIF(`email`, '')
		 ), levenstainMaxLength)),
         DATE(dob)
         INTO fullTextFilter, levenstainText, clientDOB
  FROM gaming_clients 
  WHERE client_id=clientID;

  SELECT fraud_rule_id, similarity_threshold, details_email_weight, details_dob_weight
  INTO currentFraudRuleId, currentSimilarityThreshold, currentEmailWeight, currentDobWeight
  FROM gaming_fraud_rules gfr 
  WHERE (gfr.`name` = 'similar_email' AND gfr.is_active = 1);
  
  SET similarCount = 0;
  
  IF currentFraudRuleId IS NOT NULL THEN
    
    DELETE FROM gaming_fraud_similarity_thresholds WHERE fraud_rule_id=currentFraudRuleId AND client_id_1=clientID;
    
	INSERT INTO gaming_fraud_similarity_thresholds (fraud_rule_id, client_id_1, client_id_2, similarity_threshold)
	SELECT currentFraudRuleId, clientID, x.client_id, ROUND(x.ratio, 4) 
    FROM (
		SELECT
		  gc.client_id,
		  LevenshteinRatio(
				levenstainText, 
				UPPER(RIGHT(CONCAT_WS(' ', `email`), levenstainMaxLength)) 
		   ) * currentEmailWeight
		  + IFNULL(LevenshteinRatio(clientDOB, DATE(gc.dob)),0) * currentDobWeight AS ratio
		FROM gaming_clients gc FORCE INDEX (fraud_similar_details)
		LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gc.client_id
		WHERE 
			(MATCH (`fraud_similar_details`) AGAINST (fullTextFilter IN BOOLEAN MODE)) AND 
				((gaming_fraud_rule_client_settings.block_account = 0 OR 
					gaming_fraud_rule_client_settings.block_account = NULL) AND gc.is_account_closed=0) AND 
			gc.client_id!=clientID AND 
            NOT EXISTS 
            (
				SELECT gfst.client_id_1 FROM gaming_fraud_similarity_thresholds gfst 
				WHERE gfst.fraud_rule_id = currentFraudRuleId AND gfst.client_id_1 = clientID AND gfst.client_id_2 = gc.client_id
			)                
		ORDER BY gc.client_id DESC LIMIT 25
	) AS x
	WHERE x.ratio > currentSimilarityThreshold
	ON DUPLICATE KEY UPDATE similarity_threshold=VALUES(similarity_threshold);
    
    SELECT COUNT(*) INTO similarCount FROM gaming_fraud_similarity_thresholds WHERE fraud_rule_id = currentFraudRuleId AND client_id_1 = clientID;
  
  END IF;
   
END$$

DELIMITER ;

