from Bio import SwissProt
import sys

uniprot_DAT=sys.argv[1] #"uniprot_sprot-only2016_09/uniprot_sprot.dat"

handle = open(uniprot_DAT)

for record in SwissProt.parse(handle):
	#print(record.cross_references)
	terms=record.cross_references
	go_list=''
	for i in terms:
		if 'GO' in i[0]:
			go_list+=i[1]+'; '

			#to print one GO per line
			#print(record.accessions[0]+'\t'+i[1]+'\t'+i[2]+'\t'+i[3])
	#to print many GO per 1 entry
	print(record.accessions[0]+'\t'+go_list[:-2])

	
#python extract_GO_from_uniprot_DAT.py uniprot_sprot-only2016_09/uniprot_sprot.dat

