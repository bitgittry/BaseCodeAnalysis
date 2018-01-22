
DROP function IF EXISTS `UpdateExistingReport`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `UpdateExistingReport`(
				paramReportID BIGINT(20), 
				paramVersion INT(10),
				paramHeading VARCHAR(80), 
				paramDescription MEDIUMTEXT, 
				paramTitle VARCHAR(80), 
				paramMinLevel INT(10), 
				paramReportGroupID BIGINT(20), 
				paramType INT(10),  
				paramTemplate INT(10), 
				paramCustomSql MEDIUMTEXT, 
				paramAuthor VARCHAR(80), 
				paramFooter MEDIUMTEXT, 
				paramNotes MEDIUMTEXT, 
				paramState INT(10),
				paramIconID INT(10),
				paramWithHistory INT(10),
				paramDatabaseTypeId INT(10),
				paramColTransforms MEDIUMTEXT, 
				paramResultTransforms MEDIUMTEXT, 
				paramFilters MEDIUMTEXT,
				paramUpdateByDBV INT(1)
	) RETURNS varchar(11) CHARSET utf8
BEGIN

	DECLARE paramVersionLocal INT(10);
	DECLARE paramVersionCheck INT(10);
	DECLARE paramCurrentReportVersion INT(10);
    DECLARE defaultReportGroupId BIGINT(20);

	
	
	IF (ISNULL(paramReportID)) THEN
		SELECT report_definition_id, version INTO paramVersionCheck, paramCurrentReportVersion FROM reports_definitions WHERE heading = paramHeading LIMIT 1;	
		SELECT report_definition_id, version INTO paramReportID, paramCurrentReportVersion FROM reports_definitions WHERE heading = paramHeading LIMIT 1;	
	ELSE
		SELECT report_definition_id, version INTO paramVersionCheck, paramCurrentReportVersion FROM reports_definitions WHERE report_definition_id = paramReportID LIMIT 1;	
	END IF;

		
	
	IF (paramAuthor = 0 OR paramUpdateByDBV = 1) THEN
		SELECT user_id INTO paramAuthor FROM users_main WHERE username = 'bit8_admin' AND is_global_view_user = '0' LIMIT 1;
	END IF;
    
    
      
    SELECT report_group_Id into defaultReportGroupId from reports_groups where is_default=1 LIMIT 1; 
	
	IF (ISNULL(paramVersionCheck)) THEN
		
 
		SELECT IFNULL(paramVersion, 1), IFNULL(paramVersionLocal, 0), IFNULL(paramHeading, ''), 
			   IFNULL(paramDescription, ''), IFNULL(paramTitle, ''), IFNULL(paramMinLevel, 0),               
         IF( (SELECT count(*) from reports_groups where report_group_Id = paramReportGroupID) > 0, IFNULL(paramReportGroupID, 0),defaultReportGroupId),
         IFNULL(paramType, 0), IFNULL(paramTemplate, 0), 
			   IFNULL(paramCustomSql, ''), IFNULL(paramFooter, ''), IFNULL(paramNotes, ''), IFNULL(paramState, 0), 
			   IFNULL(paramIconID, 0), IFNULL(paramWithHistory, 0), IFNULL(paramDatabaseTypeId, 0),
			   IFNULL(paramColTransforms, ''), IFNULL(paramResultTransforms, ''), IFNULL(paramFilters, '')
		INTO   paramVersion, paramVersionLocal, paramHeading, paramDescription, paramTitle, paramMinLevel, paramReportGroupID, paramType, paramTemplate,  
			   paramCustomSql, paramFooter, paramNotes, paramState, paramIconID, paramWithHistory, paramDatabaseTypeId, paramColTransforms, 
			   paramResultTransforms, paramFilters;

		IF (paramUpdateByDBV = 0) THEN
			SET paramVersionLocal = paramVersionLocal + 1;
		ELSE 
			SET paramVersionLocal = 0;
		END IF;

		
		
		INSERT INTO reports_definitions (report_definition_id, heading, description, title, min_level, report_group_id, rtype, rtemplate, customSQL, 
										 author, footer, notes, version, local_version, state, col_transforms, result_transforms, filters, purge_results, 
										 icon_id, pdf_email, pdf_password, pdf_with_password, with_history, is_custom_report, custom_url, is_visible, 
										 last_changed, report_database_type_id, updated_by_dbv)
		VALUES (paramReportID, paramHeading, paramDescription, paramTitle, paramMinLevel, paramReportGroupID, paramType, paramTemplate, paramCustomSql,
			    paramAuthor, paramFooter, paramNotes, paramVersion, paramVersionLocal, paramState, paramColTransforms, paramResultTransforms, paramFilters, 0,
			    paramIconID, NULL, NULL, 0,paramWithHistory, 0, NULL, 0, NOW(), paramDatabaseTypeId, paramUpdateByDBV);
 
	ELSE 

		
		SELECT IFNULL(paramVersion, version), IFNULL(paramVersionLocal, local_version), IFNULL(paramHeading, heading), 
			   IFNULL(paramDescription, description), IFNULL(paramTitle, title), IFNULL(paramMinLevel, min_level),			   
               IF( (SELECT count(*) from reports_groups where report_group_Id = paramReportGroupID) > 0, IFNULL(paramReportGroupID, 0),defaultReportGroupId),
               IFNULL(paramType, rtype), IFNULL(paramTemplate, rtemplate), 
			   IFNULL(paramCustomSql, customSQL), IFNULL(paramFooter, footer), IFNULL(paramNotes, notes), IFNULL(paramState, state), 
			   IFNULL(paramIconID, icon_id), IFNULL(paramWithHistory, with_history), IFNULL(paramDatabaseTypeId, report_database_type_id),
			   IFNULL(paramColTransforms, col_transforms), IFNULL(paramResultTransforms, result_transforms), IFNULL(paramFilters, filters)
		INTO   paramVersion, paramVersionLocal, paramHeading, paramDescription, paramTitle, paramMinLevel, paramReportGroupID, paramType, paramTemplate,  
			   paramCustomSql, paramFooter, paramNotes, paramState, paramIconID, paramWithHistory, paramDatabaseTypeId, paramColTransforms, 
			   paramResultTransforms, paramFilters
		FROM   reports_definitions
		WHERE  report_definition_id = paramReportID
		LIMIT 1;


		
		IF (paramVersion <= paramCurrentReportVersion AND paramUpdateByDBV = 1) THEN
			RETURN CONCAT(paramVersion, '.',paramVersionLocal); 
		END IF;
		


		IF (paramUpdateByDBV = 0) THEN
			SET paramVersionLocal = paramVersionLocal + 1;
		ELSE 
			SET paramVersionLocal = 0;
		END IF;



		
		INSERT INTO reports_definitions_history (report_definition_id, version, local_version, heading, description, title,
												min_level, report_group_id, rtype, rtemplate, customSQL, author, footer, notes, state, 
												col_transforms, result_transforms, filters, timestamp) 
		SELECT report_definition_id, version, local_version, heading, description, title, min_level, report_group_id, 
			   rtype, rtemplate, customSQL, author, footer, notes, state, col_transforms, result_transforms, filters, IFNULL(last_changed, NOW())
		FROM reports_definitions WHERE report_definition_id = paramReportID LIMIT 1
		ON DUPLICATE KEY UPDATE reports_definitions_history.report_definition_id=reports_definitions_history.report_definition_id;


		
		UPDATE reports_definitions SET version = paramVersion, local_version = paramVersionLocal, heading = paramHeading, description = paramDescription, title = paramTitle, min_level = paramMinLevel, report_group_id = paramReportGroupID, 
			   rType = paramType, rtemplate = paramTemplate, customSQL = paramCustomSql, author = paramAuthor, footer = paramFooter, notes = paramNotes, state = paramState, icon_id = paramIconID, with_history = paramWithHistory, 
			   report_database_type_id = paramDatabaseTypeId, col_transforms = paramColTransforms, result_transforms = paramResultTransforms, filters = paramFilters, 
			   last_changed = NOW(), updated_by_dbv = paramUpdateByDBV
		WHERE report_definition_id = paramReportID;
	
	END IF;


RETURN CONCAT(paramVersion, '.',paramVersionLocal);
END$$

DELIMITER ;