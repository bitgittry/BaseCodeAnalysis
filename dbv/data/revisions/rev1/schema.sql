CREATE TABLE `table1` (
  `sb_bet_id` bigint(20) NOT NULL,
  `max_sb_bet_single_id` bigint(20) DEFAULT NULL,
  `max_sb_bet_multiple_id` bigint(20) DEFAULT NULL,
  `max_sb_bet_multiple_single_id` bigint(20) DEFAULT NULL,
  `min_game_round_id` bigint(20) DEFAULT NULL,
  `max_game_round_id` bigint(20) DEFAULT NULL,
  `max_game_play_sb_id` bigint(20) DEFAULT NULL,
  `min_game_play_sb_id` bigint(20) DEFAULT NULL,
  `max_game_play_bonus_instance_id` bigint(20) DEFAULT NULL, asf sfsfsdfsdfsdfasdf
  PRIMARY KEY (`sb_bet_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

ALTER TABLE `table2` 
   ADD COLUMN `lock_uuid` VARCHAR(45) NULL AFTER `is_portal`,
   ADD INDEX `uuid` (`lock_uuid` ASC);
   
   
DROP TABLE `table3` 
   ADD COLUMN `lock_uuid` VARCHAR(45) NULL AFTER `is_portal`,
   ADD INDEX `uuid` (`lock_uuid` ASC);
           [TestMethod]
        public void GetListOrdered()
        {
            var list = new List<OrderItem>();

            list.Add(new OrderItem() { Field1 = "A", Field2 = "2" });
            list.Add(new OrderItem() { Field1 = "B", Field2 = "1" });
            list.Add(new OrderItem() { Field1 = "C", Field2 = "3" });
            list.Add(new OrderItem() { Field1 = "A", Field2 = "1" });
            list.Add(new OrderItem() { Field1 = "D", Field2 = "1" });

            var listOrderFields = new List<String>();
            listOrderFields.Add("Field1");
            listOrderFields.Add("Field2");

            var isFirstOrder = true;
            IOrderedEnumerable<OrderItem> orderedList = null;

            foreach (var field in listOrderFields)
            {
                var propertyInfo = typeof(OrderItem).GetProperty(field);

                if (isFirstOrder)
                {
                    orderedList = list.OrderBy(x => propertyInfo.GetValue(x, null));
                }
                else
                {
                    orderedList = orderedList.ThenBy(x => propertyInfo.GetValue(x, null));
                }

                isFirstOrder = false;
            }

            var newList = orderedList.ToList();
        }

        private class OrderItem
        {
            public String Field1 { get; set; }
            public String Field2 { get; set; }
        }
CREATE TABLE `table4` (
  `sb_bet_id` bigint(20) NOT NULL,
  `max_sb_bet_single_id` bigint(20) DEFAULT NULL,
  `max_sb_bet_multiple_id` bigint(20) DEFAULT NULL,
  `max_sb_bet_multiple_single_id` bigint(20) DEFAULT NULL,
  `min_game_round_id` bigint(20) DEFAULT NULL,
  `max_game_round_id` bigint(20) DEFAULT NULL,
  `max_game_play_sb_id` bigint(20) DEFAULT NULL,
  `min_game_play_sb_id` bigint(20) DEFAULT NULL,
  `max_game_play_bonus_instance_id` bigint(20) DEFAULT NULL, asf sfsfsdfsdfsdfasdf
  PRIMARY KEY (`sb_bet_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

ALTER TABLE `table5` 
   ADD COLUMN `lock_uuid` VARCHAR(45) NULL AFTER `is_portal`,
   ADD INDEX `uuid` (`lock_uuid` ASC);
   
   
DROP TABLE `table6` 
   ADD COLUMN `lock_uuid` VARCHAR(45) NULL AFTER `is_portal`,
   ADD INDEX `uuid` (`lock_uuid` ASC);
