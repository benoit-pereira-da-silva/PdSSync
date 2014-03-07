<?php

// Responses key consts

define('INFORMATIONS_KEY','informations');
define('METHOD_KEY','method');
define ('HASHMAP_FILENAME','hashMap');
define ('UID_FILENAME','uid');
define('SYSTEM_DATA_PREFIX', '.');
define('METADATA_FOLDER','.PdSSync/');


// WE use "UNIX like permissions"

// Permission applies to a tree (a tree is a graph of files ) 
// A tree    ==     "trunk" [ branch :  [ leaf , branch : [ leaf, leaf ] ];
// 1 trunk   =      1 hashmap
// 1 trunk   =      1 owner (the creator)
// 1 owner  <->     N groups

// Each leaf can historizized [ state : [ [ doer , undoer ] , ... ]
// we use for history : state, .PdSync/<relativepath>/counter , .PdSync/<relativepath>/history/0000000001.doer,000000001.undoer
// .PdSync/hashmap



///////////////////////////////
// PdSSyncPrivilege
///////////////////////////////

define ('R_OWNER' ,  400);
define ('W_OWNER' , 200);
define ('X_OWNER'  , 100);

define ('R_GROUP'  ,   40);
define ('W_GROUP' ,   20);
define ('X_GROUP'  ,   10);

define ('R_OTHER'  ,     4);
define ('W_OTHER' ,     2);
define ('X_OTHER'  ,     1);


define ('R_PRIVILEGE', 2);
define ('W_PRIVILEGE', 4);
define ('X_PRIVILEGE', 8);

define ('ANONYMOUS' , 0 );


// Command encoding


///////////////////////////////
// PdSSyncCommands
///////////////////////////////

define ('PdSCreateOrUpdate'	,	0);        // W source - un prefix the asset
define ('PdSCopy'	,					1); 		// R source W destination
define ('PdSMove'	,					2); 		// R source W destination
define ('PdSDelete'	,					3);		// W source

// PdSSyncCMDParamsRank

define ('PdSDestination'	,			1);
define ('PdSSource'			,			2);

///////////////////////////////
// PdSAdminCommands
///////////////////////////////

define ('PdsSanitize'	,	4); 		// X  on tree
define ('PdSChmod'		,	5); 		// X  on tree
define ('PdSForget'	 	,	6);		// X  on tree

// PdSAdminCMDParamRank

define ('PdSPoi'			,	1);
define ('PdSDepth'		,	2);
define ('PdSValue'		, 	3);