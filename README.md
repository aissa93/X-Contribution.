We have two scenarios: 
1. Create number sequence in newly created form 
	- Create a string EDT to be the type of the field that will maintaine Sequence number in it.
	- Creat extension class of module parmater table like (BankParameters) as the file in the same branch (BankParameters_Extension) 
	- Create extension class of number sequence module class like (NumberSeqModuleBank) as the file in the same branch (NumberSeqModuleBank_Extension).
	- Write the code consume Sequence Number in initiate form.	
	- Creat Runable class to laod the newly created parmter as the file (LoadBankModuleNumberSequence)
	

2. Create number sequence in already existed form
	
	- Use the string EDT.
	- Creat extension class of module parmater table like (BankParameters) as the file in the same branch (BankParameters_Extension) 
	- Create extension class of number sequence module class like (NumberSeqModuleBank) as the file in the same branch (NumberSeqModuleBank_Extension).
	
	- Creat Runable class to laod the newly created parmter as the file (LoadBankModuleNumberSequence)
	- Create extension class of the form (BankaccountTable) as the file in the same branch (BankaccountTable_Extension).
