/***************************************************************************************************************************

  Algorithm to impute missing IPC codes of priority filings from subsequent filings
  
  It was written by Florian Seliger in May 2019 using PostgreSQL and Patstat Spring 2019.

  Description : PostgreSQL code for PATSTAT to impute missing IPC codes (IPC_CLASS_SYMBOL from table TLS209_APPLN_IPC) for first filings. 
  When the IPC is missing, the algorithm looks into direct equivalents and other subsequent filings for the information. 
  
  Output: table PF_IPC The field 'source' indicates where the information on 
  IPC comes from :          1 = information available from the patent itself
                            2 = information availabe from the earliest direct equivalent
                            3 = information available from the earliest subsequent filing
                        
  The following 52 patent offices are browsed (EU27 + OECD + BRICS + EPO + WIPO): 
  AL,AT,AU,BE,BG,BR,CA,CH,CL,CN,CY,CZ,DE,DK,EE,EP,ES,FI,FR,GB,GR,HR, HU,IB,IE,IL,IN,IS,IT,JP,KR,LT,LU,LV,MK,MT,MX,NL,NO,NZ,PL,PT,RO,RS,RU,SE,SI,SK,SM,TR,US,ZA.

******************************************************************************************/

/*
  CREATE ALL TABLES NEEDED
*/




  -- table containing the patent offices to browse
DROP TABLE IF EXISTS po;
CREATE  TABLE po (
    patent_office CHAR(2) DEFAULT NULL
  ) ; COMMENT ON TABLE po IS 'List of patent offices to browse';
INSERT INTO po VALUES ('AL'), ('AT'), ('AU'), ('BE'), ('BG'),('BR'), ('CA'), ('CH'), ('CL'), ('CN'),('CY'), ('CZ'), ('DE'), ('DK'), ('EE'), ('EP'), ('ES'), ('FI'), ('FR'), ('GB'), ('GR'), ('HR'), ('HU'),('IB'), ('IE'), ('IL'), ('IN'), ('IS'), ('IT'), ('JP'), ('KR'), ('LT'), ('LU'), ('LV'), ('MK'), ('MT'), ('MX'), ('NL'), ('NO'), ('NZ'), ('PL'), ('PT'), ('RO'), ('RS'), ('RU'), ('SE'), ('SI'), ('SK'), ('SM'), ('TR'), ('US'), ('ZA');
DROP INDEX IF EXISTS po_idx;
CREATE INDEX po_idx ON po USING btree (patent_office);



  -- table containing the appln_id to exclude from the analysis (e.g. petty patents) for a given patent office

DROP TABLE IF EXISTS toExclude;
  CREATE  TABLE toExclude AS
      SELECT DISTINCT appln_id, publn_auth, publn_kind FROM tls211_pat_publn
      WHERE 
      (publn_auth='AU' AND (publn_kind='A3' OR publn_kind='B3' OR publn_kind='B4' OR publn_kind='C1'
      OR publn_kind='C4' OR publn_kind='D0'))
      OR 
      (publn_auth='BE' AND (publn_kind='A6' OR publn_kind='A7'))
      OR 
      (publn_auth='FR' AND (publn_kind='A3' OR publn_kind='A4' OR publn_kind='A7'))
      OR
      (publn_auth='IE' AND (publn_kind='A2' OR publn_kind='B2'))
      OR
      (publn_auth='NL' AND publn_kind='C1')
      OR 
      (publn_auth='SI' AND publn_kind='A2')
      OR
      (publn_auth='US' AND (publn_kind='E' OR publn_kind='E1' OR publn_kind='H' OR publn_kind='H1' OR publn_kind='I4' 
      OR publn_kind='P' OR publn_kind='P1' OR publn_kind='P2' OR publn_kind='P3' OR publn_kind='S1'))
      
    ;   COMMENT ON TABLE toExclude IS 'Excluded appln_id for a given po based on publn_kind';

DROP INDEX IF EXISTS exclude_idx;
CREATE INDEX exclude_idx ON toExclude USING btree (appln_id);



-- table with priority filings 
    
 -- Table containing the priority filings of a given (patent office, year)

DROP TABLE IF EXISTS PRIORITY_FILINGS;
CREATE TABLE PRIORITY_FILINGS (
appln_id INT,
appln_kind CHAR,
patent_office VARCHAR(2),
appln_filing_year INT,
appln_filing_date DATE,
type TEXT
  );


INSERT INTO PRIORITY_FILINGS
SELECT DISTINCT t1.appln_id, t1.appln_kind, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'priority'
FROM tls201_appln t1 
JOIN tls204_appln_prior t2 ON t1.appln_id = t2.prior_appln_id
LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
JOIN tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.appln_auth = t5.patent_office
WHERE (t1.appln_kind = 'A')
AND t1.internat_appln_id = 0
AND t3.appln_id IS NULL
AND t4.publn_nr IS NOT NULL 
AND t4.publn_kind !='D2'
AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016;

--newer Patstat versions: join po on receiving_office instead of appln_auth whenever appln_kind = W
INSERT INTO PRIORITY_FILINGS 
SELECT DISTINCT t1.appln_id, t1.appln_kind, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'priority'
FROM tls201_appln t1 
JOIN tls204_appln_prior t2 ON t1.appln_id = t2.prior_appln_id
LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
JOIN tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.appln_auth = t5.patent_office
--JOIN po t5 ON t1.receiving_office = t5.patent_office
WHERE (t1.appln_kind = 'W')
AND t1.internat_appln_id = 0
AND t3.appln_id IS NULL
AND t4.publn_nr IS NOT NULL 
AND t4.publn_kind !='D2'
AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016;


 
INSERT INTO PRIORITY_FILINGS
SELECT DISTINCT t1.appln_id, t1.appln_kind, t1.appln_auth AS patent_office, t1.appln_filing_year, t1.appln_filing_date, 'pct'
FROM tls201_appln t1 
LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
JOIN tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON (t1.appln_auth = t5.patent_office)
--JOIN po t5 ON (t1.receiving_office = t5.patent_office)

  LEFT OUTER JOIN PRIORITY_FILINGS t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind = 'W')
AND t1.internat_appln_id = 0 and nat_phase = 'N' and reg_phase = 'N'
AND t1.appln_id = t1.earliest_filing_id
AND t3.appln_id IS NULL
AND t4.publn_nr IS NOT NULL 
AND t4.publn_kind !='D2'
AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;


INSERT INTO PRIORITY_FILINGS
SELECT DISTINCT t1.appln_id, t1.appln_kind, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'continual'
FROM tls201_appln t1 
JOIN tls216_appln_contn t2 ON t1.appln_id = t2.parent_appln_id
LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
JOIN tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.appln_auth = t5.patent_office

    LEFT OUTER JOIN PRIORITY_FILINGS t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind = 'A')
AND t1.internat_appln_id = 0
AND t3.appln_id IS NULL
AND t4.publn_nr IS NOT NULL 
AND t4.publn_kind !='D2'
AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;

INSERT INTO PRIORITY_FILINGS 
SELECT DISTINCT t1.appln_id, t1.appln_kind, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'continual'
FROM tls201_appln t1 
JOIN tls216_appln_contn t2 ON t1.appln_id = t2.parent_appln_id
LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
JOIN tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.appln_auth = t5.patent_office
--JOIN po t5 ON t1.receiving_office = t5.patent_office

      LEFT OUTER JOIN PRIORITY_FILINGS t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind = 'W')
AND t1.internat_appln_id = 0
AND t3.appln_id IS NULL
AND t4.publn_nr IS NOT NULL 
AND t4.publn_kind !='D2'
AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;

INSERT INTO PRIORITY_FILINGS
SELECT DISTINCT t1.appln_id, t1.appln_kind, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'tech_rel'
FROM tls201_appln t1 
JOIN tls205_tech_rel t2 ON t1.appln_id = t2.tech_rel_appln_id
LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
JOIN tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.appln_auth = t5.patent_office

      LEFT OUTER JOIN PRIORITY_FILINGS t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind = 'A')
AND t1.internat_appln_id = 0
AND t3.appln_id IS NULL
AND t4.publn_nr IS NOT NULL 
AND t4.publn_kind !='D2'
AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;

INSERT INTO PRIORITY_FILINGS
SELECT DISTINCT t1.appln_id, t1.appln_kind, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'tech_rel'
FROM tls201_appln t1 
JOIN tls205_tech_rel t2 ON t1.appln_id = t2.tech_rel_appln_id
LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
JOIN tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.appln_auth = t5.patent_office
--JOIN po t5 ON t1.receiving_office = t5.patent_office

      LEFT OUTER JOIN PRIORITY_FILINGS t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind = 'W')
AND t1.internat_appln_id = 0
AND t3.appln_id IS NULL
AND t4.publn_nr IS NOT NULL 
AND t4.publn_kind !='D2'
AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;

-- Singletons
INSERT INTO PRIORITY_FILINGS
SELECT DISTINCT t1.appln_id, t1.appln_kind, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'single'
FROM patstat.tls201_appln t1 
JOIN (SELECT docdb_family_id from patstat.tls201_appln group by docdb_family_id having count(distinct appln_id) = 1) as t2
ON t1.docdb_family_id = t2.docdb_family_id
LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.appln_auth = t5.patent_office

	LEFT OUTER JOIN PRIORITY_FILINGS t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind = 'A')
AND t1.internat_appln_id = 0
AND t3.appln_id IS NULL
AND t4.publn_nr IS NOT NULL 
AND t4.publn_kind !='D2'
AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;

INSERT INTO PRIORITY_FILINGS
SELECT DISTINCT t1.appln_id, t1.appln_kind, t1.appln_auth, t1.appln_filing_year, t1.appln_filing_date, 'single'
FROM patstat.tls201_appln t1 
JOIN (SELECT docdb_family_id from patstat.tls201_appln group by docdb_family_id having count(distinct appln_id) = 1) as t2
ON t1.docdb_family_id = t2.docdb_family_id
LEFT OUTER JOIN toExclude t3 ON t1.appln_id = t3.appln_id
--JOIN patstat.tls211_pat_publn t4 ON t1.appln_id = t4.appln_id
JOIN po t5 ON t1.appln_auth = t5.patent_office
JOIN po t5 ON t1.receiving_office = t5.patent_office

      LEFT OUTER JOIN PRIORITY_FILINGS t7 on t1.appln_id = t7.appln_id 

WHERE (t1.appln_kind = 'W')
AND t1.internat_appln_id = 0
AND t3.appln_id IS NULL
AND t4.publn_nr IS NOT NULL 
AND t4.publn_kind !='D2'
AND t1.appln_filing_year >=1980 AND t1.appln_filing_year<2016
AND t7.appln_id is null
;

DROP INDEX IF EXISTS pf_idx_, pf_idx2_, pf_idx3_;
CREATE INDEX pf_idx_ ON PRIORITY_FILINGS USING btree (appln_id);
CREATE INDEX pf_idx2_ ON PRIORITY_FILINGS USING btree (patent_office);
CREATE INDEX pf_idx3_ ON PRIORITY_FILINGS USING btree (appln_filing_year);


 




/* 
Create the tables that will be used in main function to impute missing information
*/


	-- A. Information that is directly available (source = 1)
DROP TABLE IF EXISTS PRIORITY_FILINGS1_TECH;
CREATE TABLE PRIORITY_FILINGS1_TECH AS (
	--first of all we need all priority filings with technology information in Patstat 
SELECT DISTINCT t1.appln_id, t1.appln_kind, t1.patent_office, t1.appln_filing_date, t1.appln_filing_year, 
  ipc_class_symbol, ipc_class_level, ipc_version, ipc_value, ipc_position, ipc_gener_auth, type
FROM PRIORITY_FILINGS t1 
JOIN TLS209_APPLN_IPC t2 ON t1.appln_id = t2.appln_id ) ;
    --second, we need all priority filings without any technology information
INSERT INTO PRIORITY_FILINGS1_TECH
SELECT DISTINCT t1.appln_id, t1.appln_kind, t1.patent_office, t1.appln_filing_date, t1.appln_filing_year, 
  ipc_class_symbol, ipc_class_level, ipc_version, ipc_value, ipc_position, ipc_gener_auth, type
FROM PRIORITY_FILINGS t1 
LEFT JOIN TLS209_APPLN_IPC t2 ON t1.appln_id = t2.appln_id
	WHERE t2.appln_id IS NULL;
	

DROP INDEX IF EXISTS pri1t_idx,  pri1t_office_idx, pri1t_year;
CREATE INDEX pri1t_idx ON PRIORITY_FILINGS1_TECH USING btree (appln_id);
CREATE INDEX pri1t_office_idx ON PRIORITY_FILINGS1_TECH USING btree (patent_office);
CREATE INDEX pri1t_year_idx ON PRIORITY_FILINGS1_TECH USING btree (appln_filing_year);



	-- B. Prepare a pool of all potential second filings
DROP TABLE IF EXISTS SUBSEQUENT_FILINGS1_TECH;
CREATE  TABLE SUBSEQUENT_FILINGS1_TECH AS (
SELECT DISTINCT t1.appln_id, t1.appln_kind, t.subsequent_id, t1.patent_office, t1.appln_filing_date, t1.appln_filing_year, 
t.subsequent_date, t.nb_priorities, type
FROM PRIORITY_FILINGS1_TECH t1 

JOIN (SELECT t1.appln_id, t3.appln_id AS subsequent_id, t3.appln_filing_date AS subsequent_date, max(t4.prior_appln_seq_nr) AS nb_priorities
	  FROM PRIORITY_FILINGS1_TECH t1 
	  INNER JOIN tls204_appln_prior t2 ON t2.prior_appln_id = t1.appln_id
	  INNER JOIN tls201_appln t3 ON t3.appln_id = t2.appln_id
	  INNER JOIN tls204_appln_prior t4 ON t4.appln_id = t3.appln_id
    where type = 'priority'
      GROUP BY t1.appln_id, t3.appln_id, t3.appln_filing_date 	  
) AS t ON t1.appln_id = t.appln_id
ORDER BY t1.appln_id, t.subsequent_date ASC);

INSERT INTO SUBSEQUENT_FILINGS1_TECH
SELECT DISTINCT t1.appln_id, t1.appln_kind, t.subsequent_id, t1.patent_office, t1.appln_filing_date, t1.appln_filing_year, 
t.subsequent_date, t.nb_priorities, type
FROM PRIORITY_FILINGS1_TECH t1 

JOIN (SELECT t1.appln_id, t3.appln_id AS subsequent_id, t3.appln_filing_date AS subsequent_date, max(count) AS nb_priorities
	  FROM PRIORITY_FILINGS1_TECH t1 
	  INNER JOIN tls216_appln_contn t2 ON t2.parent_appln_id = t1.appln_id
	  INNER JOIN tls201_appln t3 ON t3.appln_id = t2.appln_id
	  INNER JOIN  (select appln_id, count(*) from tls216_appln_contn group by appln_id) as t4 ON t4.appln_id = t3.appln_id
    where type = 'continual'
      GROUP BY t1.appln_id, t3.appln_id, t3.appln_filing_date 	  
) AS t ON t1.appln_id = t.appln_id
ORDER BY t1.appln_id, t.subsequent_date ASC;

INSERT INTO SUBSEQUENT_FILINGS1_TECH
SELECT DISTINCT t1.appln_id, t1.appln_kind, t.subsequent_id, t1.patent_office, t1.appln_filing_date, t1.appln_filing_year, 
t.subsequent_date, t.nb_priorities, type
FROM PRIORITY_FILINGS1_TECH t1 

JOIN (SELECT t1.appln_id, t3.appln_id AS subsequent_id, t3.appln_filing_date AS subsequent_date, max(count) AS nb_priorities
	  FROM PRIORITY_FILINGS1_TECH t1 
	  INNER JOIN TLS205_TECH_REL t2 ON t2.tech_rel_appln_id = t1.appln_id
	  INNER JOIN tls201_appln t3 ON t3.appln_id = t2.appln_id
	  INNER JOIN  (select appln_id, count(*) from TLS205_TECH_REL group by appln_id) as t4 ON t4.appln_id = t3.appln_id
    where type = 'tech_rel'
      GROUP BY t1.appln_id, t3.appln_id, t3.appln_filing_date 	  
) AS t ON t1.appln_id = t.appln_id
ORDER BY t1.appln_id, t.subsequent_date ASC;

INSERT INTO SUBSEQUENT_FILINGS1_TECH
SELECT DISTINCT t1.appln_id, t1.appln_kind, t.subsequent_id, t1.patent_office, t1.appln_filing_date, t1.appln_filing_year, 
t.subsequent_date, 1, type
FROM PRIORITY_FILINGS1_TECH t1 

JOIN (SELECT t1.appln_id, t2.appln_id AS subsequent_id, t2.appln_filing_date AS subsequent_date
	  FROM PRIORITY_FILINGS1_TECH t1 
	  INNER JOIN tls201_appln t2 ON t1.appln_id = t2.internat_appln_id
    where type = 'pct'
    AND t2.internat_appln_id != 0 and reg_phase = 'Y'
      GROUP BY t1.appln_id, t2.appln_id, t2.appln_filing_date 	  
) AS t ON t1.appln_id = t.appln_id
ORDER BY t1.appln_id, t.subsequent_date ASC;

INSERT INTO SUBSEQUENT_FILINGS1_TECH
SELECT DISTINCT t1.appln_id, t1.appln_kind, t.subsequent_id, t1.patent_office, t1.appln_filing_date, t1.appln_filing_year, 
t.subsequent_date, 2, type
FROM PRIORITY_FILINGS1_TECH t1 

JOIN (SELECT t1.appln_id, t2.appln_id AS subsequent_id, t2.appln_filing_date AS subsequent_date
	  FROM PRIORITY_FILINGS1_TECH t1 
	  INNER JOIN tls201_appln t2 ON t1.appln_id = t2.internat_appln_id
    where type = 'pct'
    AND t2.internat_appln_id != 0 and nat_phase = 'Y'
      GROUP BY t1.appln_id, t2.appln_id, t2.appln_filing_date 	  
) AS t ON t1.appln_id = t.appln_id
ORDER BY t1.appln_id, t.subsequent_date ASC;


DROP INDEX IF EXISTS sec1t_idx, sec1t_pers_idx, sec1t_office_idx, sec1t_year_idx;							
CREATE INDEX sec1t_idx ON SUBSEQUENT_FILINGS1_TECH USING btree (appln_id);
CREATE INDEX sec1t_sub_idx ON SUBSEQUENT_FILINGS1_TECH USING btree (subsequent_id);
CREATE INDEX sec1t_office_idx ON SUBSEQUENT_FILINGS1_TECH USING btree (patent_office);
CREATE INDEX sec1t_year_idx ON SUBSEQUENT_FILINGS1_TECH USING btree (appln_filing_year);	

	-- B.1 Information from equivalents (source = 2)
	-- B.1.1 Find all the relevant information
DROP TABLE IF EXISTS EQUIVALENTS2_TECH;
CREATE  TABLE EQUIVALENTS2_TECH AS (
SELECT  t1.appln_id, t1.subsequent_id, t1.subsequent_date, t1.patent_office, t1.appln_filing_date, t1.appln_filing_year, 
  ipc_class_symbol, ipc_class_level, ipc_version, ipc_value, ipc_position, ipc_gener_auth, type
FROM SUBSEQUENT_FILINGS1_TECH t1 
LEFT OUTER JOIN TLS209_APPLN_IPC t2 ON t1.subsequent_id = t2.appln_id
WHERE t1.nb_priorities = 1  );
DROP INDEX IF EXISTS equ2t_idx, equ2t_sub_idx,  equ2t_office_idx, equ2t_year_idx;
CREATE INDEX equ2t_idx ON EQUIVALENTS2_TECH USING btree (appln_id);
CREATE INDEX equ2t_sub_idx ON EQUIVALENTS2_TECH USING btree (subsequent_id);
CREATE INDEX equ2t_office_idx ON EQUIVALENTS2_TECH USING btree (patent_office);
CREATE INDEX equ2t_year_idx ON EQUIVALENTS2_TECH USING btree (appln_filing_year);	


      -- B.1.2 Select the most appropriate (i.e. earliest) equivalent
DROP TABLE IF EXISTS EARLIEST_EQUIVALENT2_TECH;
CREATE  TABLE EARLIEST_EQUIVALENT2_TECH AS 
SELECT t1.appln_id, subsequent_id, 
    ipc_class_symbol, ipc_class_level, ipc_version, ipc_value, ipc_position, ipc_gener_auth, type,
  min FROM EQUIVALENTS2_TECH t1
JOIN (SELECT appln_id, min(subsequent_date) AS min
FROM EQUIVALENTS2_TECH
GROUP BY appln_id ) AS t2 ON (t1.appln_id = t2.appln_id AND t1.subsequent_date = t2.min);
DROP INDEX IF EXISTS eequ2t_idx, eequ2t_sub_idx;
CREATE INDEX eequ2t_idx ON EARLIEST_EQUIVALENT2_TECH USING btree (appln_id);
CREATE INDEX eequ2t_sub_idx ON EARLIEST_EQUIVALENT2_TECH USING btree (subsequent_id);

	-- deal with cases where we have several equivalents (select only one)
DROP TABLE IF EXISTS EARLIEST_EQUIVALENT2_TECH_;
CREATE TABLE EARLIEST_EQUIVALENT2_TECH_ AS
SELECT t1.* FROM EARLIEST_EQUIVALENT2_TECH t1 JOIN
(SELECT appln_id, min(subsequent_id)
FROM EARLIEST_EQUIVALENT2_TECH
GROUP BY appln_id) as t2
ON t1.appln_id = t2.appln_id AND t1.subsequent_id = t2.min;
DROP INDEX IF EXISTS eequ_idx_, eequ_sub_idx_;
CREATE INDEX eequ2_idx_ ON EARLIEST_EQUIVALENT2_TECH_ USING btree (appln_id);
CREATE INDEX eequ2_sub_idx_ ON EARLIEST_EQUIVALENT2_TECH_ USING btree (subsequent_id);
	
	-- B.2 Information from other subsequent filings (source = 3)
	-- B.2.1 Find information from subsequent filings for patents that have not yet been identified via their potential equivalent(s)
DROP TABLE IF EXISTS OTHER_SUBSEQUENT_FILINGS3_TECH;
CREATE  TABLE OTHER_SUBSEQUENT_FILINGS3_TECH AS (
SELECT  t1.appln_id, t1.subsequent_id, t1.subsequent_date, t1.patent_office, t1.appln_filing_date, t1.appln_filing_year, 
    ipc_class_symbol, ipc_class_level, ipc_version, ipc_value, ipc_position, ipc_gener_auth, type
FROM SUBSEQUENT_FILINGS1_TECH t1 
LEFT OUTER JOIN TLS209_APPLN_IPC t2 ON t1.subsequent_id = t2.appln_id
WHERE t1.nb_priorities > 1  );
DROP INDEX IF EXISTS other3t_idx, other3t_sub_idx, other3t_office_idy, other3t_year_idx;
CREATE INDEX other3t_idx ON OTHER_SUBSEQUENT_FILINGS3_TECH USING btree (appln_id);
CREATE INDEX other3t_sub_idx ON OTHER_SUBSEQUENT_FILINGS3_TECH USING btree (subsequent_id);
CREATE INDEX other3t_office_idx ON OTHER_SUBSEQUENT_FILINGS3_TECH USING btree (patent_office);
CREATE INDEX other3t_year_idx ON OTHER_SUBSEQUENT_FILINGS3_TECH USING btree (appln_filing_year);	
	
	
    -- B.2.2 Select the most appropriate (i.e. earliest) subsequent filing
DROP TABLE IF EXISTS EARLIEST_SUBSEQUENT_FILING3_TECH;
CREATE  TABLE EARLIEST_SUBSEQUENT_FILING3_TECH AS 
SELECT t1.appln_id, subsequent_id, 
    ipc_class_symbol, ipc_class_level, ipc_version, ipc_value, ipc_position, ipc_gener_auth, type,
  min FROM OTHER_SUBSEQUENT_FILINGS3_TECH t1
JOIN (SELECT appln_id, min(subsequent_date) AS min 
FROM OTHER_SUBSEQUENT_FILINGS3_TECH
GROUP BY appln_id) AS t2 ON (t1.appln_id = t2.appln_id AND t1.subsequent_date = t2.min);
DROP INDEX IF EXISTS esub3t_idx, esub3t_sub_idx;
CREATE INDEX esub3t_idx ON EARLIEST_SUBSEQUENT_FILING3_TECH USING btree (appln_id);
CREATE INDEX esub3t_sub_idx ON EARLIEST_SUBSEQUENT_FILING3_TECH USING btree (subsequent_id);

	-- deal with cases where we have several earliest equivalents (select only one)
DROP TABLE IF EXISTS EARLIEST_SUBSEQUENT_FILING3_TECH_;
CREATE TABLE EARLIEST_SUBSEQUENT_FILING3_TECH_ AS
SELECT t1.* FROM EARLIEST_SUBSEQUENT_FILING3_TECH t1 JOIN
(SELECT appln_id, min(subsequent_id)
FROM EARLIEST_SUBSEQUENT_FILING3_TECH
GROUP BY appln_id) AS t2
ON t1.appln_id = t2.appln_id AND t1.subsequent_id = t2.min;
DROP INDEX IF EXISTS esub3_idx_, esub3_sub_idx_;
CREATE INDEX esub3_idx_ ON EARLIEST_SUBSEQUENT_FILING3_TECH_ USING btree (appln_id);
CREATE INDEX esub3_sub_idx_ ON EARLIEST_SUBSEQUENT_FILING3_TECH_ USING btree (subsequent_id);





-- TABLE containing information on priority filings and IPC codes

DROP TABLE IF EXISTS TABLE_USE_IPC;
CREATE TABLE TABLE_USE_IPC AS
SELECT * FROM PRIORITY_FILINGS1_TECH
;
CREATE INDEX TABLE_USE_IPC_APPLN_ID ON TABLE_USE_IPC USING btree (appln_id);


-- Table containing the information for a given (patent office, year)
DROP TABLE IF EXISTS TABLE_IPC;
CREATE  TABLE TABLE_IPC (
	appln_id INTEGER DEFAULT NULL,
	ipc_class_level CHAR(1) DEFAULT NULL,
	ipc_class_symbol CHAR(15) DEFAULT NULL,
	ipc_gener_auth CHAR(2) DEFAULT NULL,
	ipc_position CHAR(1) DEFAULT NULL,
	ipc_value CHAR(1) DEFAULT NULL,
	ipc_version DATE DEFAULT NULL,
	source INT DEFAULT NULL,
    type TEXT DEFAULT NULL
	); 
	
	


	

/* 
  MAIN PROCEDURE
*/

    
     -- A Insert information that is directly available (source = 1)
  
     INSERT INTO TABLE_IPC  
     SELECT  appln_id, ipc_class_level, ipc_class_symbol, ipc_gener_auth, ipc_position, ipc_value, ipc_version, 1, type
     FROM TABLE_USE_IPC t_
     WHERE t_.ipc_class_symbol IS NOT NULL;
     
     DELETE FROM TABLE_USE_IPC t WHERE t.appln_id IN (SELECT appln_id FROM TABLE_IPC);    
     
	   -- B.1 Add the information from each selected equivalent
     INSERT INTO TABLE_IPC
     SELECT 
     t_.appln_id,
     t_.ipc_class_level, 
     t_.ipc_class_symbol, 
     t_.ipc_gener_auth, 
     t_.ipc_position, 
     t_.ipc_value, 
     t_.ipc_version,
     2,
     t_.type
     FROM (
     SELECT t1.appln_id, ipc_class_level, ipc_class_symbol, ipc_gener_auth, ipc_position, ipc_value, ipc_version, type
     FROM EARLIEST_EQUIVALENT2_TECH_ t1 
     JOIN (
	   SELECT DISTINCT appln_id FROM
	   TABLE_USE_IPC) AS t2
	   ON  t1.appln_id = t2.appln_id
	    WHERE ipc_class_symbol IS NOT NULL
	   ) AS t_
     ;
	
	   DELETE FROM TABLE_USE_IPC t WHERE t.appln_id IN (SELECT appln_id FROM TABLE_IPC);    
 

    -- B.2 Add the information from each selected subsequent filing
	   INSERT INTO TABLE_IPC
     SELECT 
     t_.appln_id,
     t_.ipc_class_level, 
     t_.ipc_class_symbol, 
     t_.ipc_gener_auth, 
     t_.ipc_position, 
     t_.ipc_value, 
     t_.ipc_version,
     3,
     t_.type
     FROM (
     SELECT t1.appln_id, ipc_class_level, ipc_class_symbol, ipc_gener_auth, ipc_position, ipc_value, ipc_version, type
     FROM EARLIEST_SUBSEQUENT_FILING3_TECH_ t1
     JOIN (
	   SELECT DISTINCT appln_id FROM
	   TABLE_USE_IPC) AS t2
	   ON  t1.appln_id = t2.appln_id
 	    WHERE ipc_class_symbol IS NOT NULL
	   ) AS t_
     ;

  	 DELETE FROM TABLE_USE_IPC t WHERE t.appln_id IN (SELECT appln_id FROM TABLE_IPC);    

     CREATE INDEX table_ipc_appln_id ON TABLE_IPC(appln_id);
	
    -- Table with tech fields

    DROP TABLE IF EXISTS PF_IPC;
    CREATE TABLE PF_IPC (
	  appln_id INTEGER DEFAULT NULL,
	  patent_office CHAR(2) DEFAULT NULL,
	  priority_date date DEFAULT NULL,
	  priority_year INTEGER DEFAULT NULL,
	  ipc_class_level CHAR(1) DEFAULT NULL,
	  ipc_class_symbol CHAR(15) DEFAULT NULL,
	  ipc_gener_auth CHAR(2) DEFAULT NULL,
	  ipc_position CHAR(1) DEFAULT NULL,
	  ipc_value CHAR(1) DEFAULT NULL,
	  ipc_version DATE DEFAULT NULL,
	  source INT DEFAULT NULL,
      type TEXT DEFAULT NULL
	  );  

    

     -- E. Job done, insert into final table 
     INSERT INTO PF_IPC
     SELECT DISTINCT t1.appln_id, t2.patent_office, t2.appln_filing_date, t2.appln_filing_year, ipc_class_level, ipc_class_symbol, ipc_gener_auth, ipc_position, ipc_value, ipc_version, source, t1.type
     FROM TABLE_IPC t1 JOIN PRIORITY_FILINGS t2 ON t1.appln_id = t2.appln_id;


							
	 CREATE INDEX PF_IPC_APPLN_ID ON PF_IPC(appln_id);
	 CREATE INDEX PF_IPC_YEAR ON PF_IPC(priority_year);
											 
							
   
     
    


DROP TABLE IF EXISTS po;
DROP TABLE IF EXISTS toExclude;
DROP TABLE IF EXISTS TABLE_TO_BE_FILLED_TECH;
DROP TABLE IF EXISTS PRIORITY_FILINGS1_TECH;
DROP TABLE IF EXISTS SUBSEQUENT_FILINGS1_TECH;
DROP TABLE IF EXISTS EQUIVALENTS2_TECH;
DROP TABLE IF EXISTS EARLIEST_EQUIVALENT2_TECH;
DROP TABLE IF EXISTS OTHER_SUBSEQUENT_FILINGS3_TECH;
DROP TABLE IF EXISTS EARLIEST_SUBSEQUENT_FILING3_TECH;
