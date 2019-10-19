from Bio import SwissProt
import sys

uniprot_DAT=sys.argv[1] #"uniprot_sprot-only2016_09/uniprot_sprot.dat"

handle = open(uniprot_DAT)

for record in SwissProt.parse(handle):
	terms=record.cross_references
	go_list=''
	for i in terms:
		if 'GO' in i[0]:
			go_list+=i[1]+'; '

	if 'Name=' in record.gene_name:
		if '{' in record.gene_name:
			gene_name=record.gene_name.split(';')[0].replace('Name=','').split('{')[0].replace(',','_')
		else:
			gene_name=record.gene_name.split(';')[0].replace('Name=','').replace(',','_')
	else:
		gene_name='NA'

	if 'RecName: Full=' in record.description:
		if '{' in record.description:
			desc=record.description.split('{')[0].split(';')[0].replace('RecName: Full=','').replace(',','_').replace('\'','')
		else:
			desc=record.description.split(';')[0].replace('RecName: Full=','').replace(',','_').replace('\'','')
	else:
		desc='NA'
	
	if go_list=='':
		go_list='NA'
	else:
		go_list=go_list[:-2]

	print('>'+record.accessions[0]+','+gene_name+','+desc+','+go_list+'\n'+record.sequence)
	
#python extract_GO_from_uniprot_DAT.py uniprot_sprot-only2016_09/uniprot_sprot.dat

