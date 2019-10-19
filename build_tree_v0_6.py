
from Bio.Phylo.TreeConstruction import _Matrix,DistanceTreeConstructor,_DistanceMatrix
from Bio import Phylo
from Bio.Align.Applications import MuscleCommandline
from Bio import SeqIO, pairwise2, Align, AlignIO
import os
import subprocess
from subprocess import PIPE,STDOUT,Popen,call
import shutil
from Bio.Phylo.TreeConstruction import DistanceCalculator
import sqlite3
import random
import itertools, sys
from collections import Counter
import random
from deap import creator, base, tools, algorithms
import numpy
import sys
import itertools, sys

#conda install -c etetoolkit ete3 ete_toolchain
from ete3 import Tree
from ete3 import PhyloTree, TreeStyle, faces, AttrFace
from ete3 import NCBITaxa

#make new dependency
#conda activate build_tree

#dependencies
#conda install -c anaconda biopython
#conda install -c anaconda sqlite
#conda install -c anaconda scipy
#conda install -c etetoolkit ete3 ete_toolchain

##### Version ######
## v.0.6 - add method 'call_taxonomy'
## v.0.5 - combine methods from 'make_network_input.py in to this script'
## v.0.4 - apply random walk algorithm to retrieve real cluster from igraph network  
## v.0.3 - change phylo score calculation to include 1 and 2 genome conservation 
##		 - build Genetic algorithm to optimize RF score between trees
##		 - Change pairwise alignment to Vsearch, extreamly fast
##		 - Add multiple seq alignment to GA optimization
## v.0.2 - add method building phylo_tree using Ete3 , add method compare_tree
## v.0.1 - update Phylo score by setting minimum value for closely related species in the case that 16sRNAs are identical




#########################################################################################
###################################### Methods ##########################################
#########################################################################################

def blast_get_pident(fasta):
	mkdb = 'makeblastdb -in '+fasta+' -dbtype nucl'
	run_mkdb = Popen(mkdb,shell=True,stdin=PIPE, stdout=PIPE, stderr=STDOUT, close_fds=True,encoding='utf8')

	blast = "blastn -db "+fasta+" -query "+fasta+" -out "+fasta+".blastout -outfmt '6 qseqid sseqid evalue pident qstart qend qlen slen length sstart send' -num_threads 4"
	#blast option -task "blastn-short", -qcov_hsp_perc 100 
	run_blast = Popen(mkdb,shell=True,stdin=PIPE, stdout=PIPE, stderr=STDOUT, close_fds=True,encoding='utf8')	
	output = ps.stdout.read()


def pairwise_ali_ori(fasta):


	seq_dict={}
	key=[]
	for seq_rec in SeqIO.parse(fasta,"fasta"):
		seq_dict[seq_rec.id]=seq_rec.seq
		key.append(seq_rec.id)

	combos = itertools.combinations(key, 2) #make combinations of the sequences
	for k,v in combos:

		aln = pairwise2.align.globalxx(seq_dict[k],seq_dict[v])
		seq_ident=aln[0][2]
		seq_len=aln[0][4]+1
		p_ident=seq_ident/float(seq_len)

		print(k,v)
		print('ident',seq_ident)
		print('len',seq_len)
		print('pident',p_ident)

		#print(aln)
		#print(pairwise2.format_alignment(*aln[0]))
#pairwise_ali('./INPUT/RF02376.fasta')


ncbi = NCBITaxa()
def call_taxonomy(accession,tax_level): #accession e.g. NC_00911
	cmd='esearch -db nucleotide -query "'+str(accession)+'"|esummary|xtract -pattern TaxId -element TaxId'
	print(cmd)
	ps=Popen(cmd,shell=True, stdout=PIPE, encoding='utf8') #use utf8 to remove b'..'
	output = ps.stdout.read().rstrip()
	print(output)

	cmd2='esearch -db nucleotide -query "'+str(accession)+'"|esummary|xtract -pattern Organism -element Organism'
	print(cmd2)
	ps2=Popen(cmd2,shell=True, stdout=PIPE, encoding='utf8') #use utf8 to remove b'..'
	org_name = ps2.stdout.read().rstrip()

	if output != '':
		tax_list=[]
		tax_level_found='no'
		for lineage in ncbi.get_lineage(output) : #lineage is taxonomy id for each level

			if tax_level == ncbi.get_rank([lineage]).get(lineage):
				tax_level_found='yes'
				ranking=ncbi.get_rank([lineage]).get(lineage)
				name_rank=str(ncbi.get_taxid_translator([lineage]).get(lineage))
				selected_taxID=lineage
				tax_ranking=ranking+' : '+name_rank+' ('+str(selected_taxID)+')'
		if tax_level_found=='no':
			tax_ranking='N/A'
			selected_taxID='N/A'
		print(tax_ranking)
	else:
		print('Query ID',accession,' not found!!')
	print('Done! calling taxonomy')

	return selected_taxID, tax_ranking, org_name

#call_taxonomy('NC_000912','species') #tax_level follows ncbi taxonomy: e.g. superkingdom, phylum, order, family, genus, species


#make_network_input(sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4])
#usage 
#python make_network_input.py testfile_cluster_table.txt testfile_synteny_table.txt nb_test.out 'False'
#'False,TRUE' use if know mark id for setting the point for changing the prefix of query label
def make_network_input(cluster_table,neighbor_table,out_file,prefix_change): 
	#make list of cluster table
	cluster_dict={}
	for cluster in open(cluster_table):
		#print(cluster)
		if 'cluster_' in cluster:
			cluster=cluster.replace('\n','')
			cluster=cluster.split('\t')
			member=cluster[1].split(',')
			cluster[0]=cluster[0].replace('cluster_','c.')
			for i in member:
				#print(cluster[0],i)
				cluster_dict[str(i)] = str(cluster[0])
				
	#print(str(cluster_dict))

	#assign cluster number to neighborhood genes
	nb_cluster=[]
	q_label=1
	q_list=[]
	q_list2=[]

	q_prefix='q.' #initial query prefix
	mark_ID='CP000680.1_1126779' #for setting the point for changing the prefix of query label

	for line_nb in open(neighbor_table):
		line_nb=line_nb.replace('\n','')		
		if 'neighbourhood_genes' not in line_nb:
			line_nb=line_nb.split('\t')

			nb_l=line_nb[4].split(',') #nb_l = neighborhood list

			for j in nb_l:
				#for 
				if prefix_change == 'True' and line_nb[0] == mark_ID:
					#print(line_nb[0])
					q_prefix='n.' #query prefix after match the ID condition

				try:
					#print(line_nb[0],cluster_dict[str(j)])
					q_list.append(q_prefix+str(q_label)+'\t'+line_nb[0])
					q_list2.append(q_prefix+str(q_label)+','+line_nb[1]+','+line_nb[0].split('_')[1]+','+line_nb[0].split('_')[0]+','+line_nb[3])
					nb_cluster.append(q_prefix+str(q_label)+','+cluster_dict[str(j)])
					
				except KeyError:

					print(j,"not found in cluster!")

			q_label+=1
					
	nb_cluster=((set(nb_cluster)))
	q_list=((set(q_list)))
	q_list2=((set(q_list2)))

	w2label=open('query_label.out','w')
	for n in q_list:
		w2label.write(n+'\n')
	w2label.close()

	w2label=open('mapping.q','w')
	for n in q_list2:
		w2label.write(n+'\n')
	w2label.close()

	w2file=open(out_file,'w')
	for n in nb_cluster:
		w2file.write(n+'\n')
	w2file.close()

def random_color_code():
	r = lambda: random.randint(0,255)
	return '#%02X%02X%02X' % (0,r(),r()) #random color except red tone

def make_network_input_2(cluster_table,neighbor_table,out_file,prefix_change, taxonomy_level): #*add taxonomy_level
	#make list of cluster table
	cluster_dict={}
	for cluster in open(cluster_table):
		#print(cluster)
		if 'cluster_' in cluster:
			cluster=cluster.replace('\n','')
			cluster=cluster.split('\t')
			member=cluster[1].split(',')
			cluster[0]=cluster[0].replace('cluster_','c.')
			for i in member:
				#print(cluster[0],i)
				cluster_dict[str(i)] = str(cluster[0])
				
	#print(str(cluster_dict))

	#assign cluster number to neighborhood genes
	nb_cluster=[]
	q_label=1
	q_list=[]
	q_list2=[]
	used_tax_color_code={}
	used_color_code=[]
	used_tax_level={}

	q_prefix='q.' #initial query prefix
	mark_ID='CP000680.1_1126779' #for setting the point for changing the prefix of query label

	for line_nb in open(neighbor_table):
		line_nb=line_nb.replace('\n','')		
		if 'neighbourhood_genes' not in line_nb:
			line_nb=line_nb.split('\t')

			nb_l=line_nb[4].split(',') #nb_l = neighborhood list

			if line_nb[3].split('.')[0] not in used_tax_color_code: #line_nb[3] => NC_000.911.1
				tax_level=call_taxonomy(line_nb[3].split('.')[0],taxonomy_level)#return [0]Tax ID of selected level, [1]name of taxonomy level, [2]org_name
				if str(tax_level[0]) not in used_tax_level:
					print(str(tax_level[0]))
					tax_color_code=random_color_code()
					while tax_color_code in used_color_code:
						tax_color_code=random_color_code()
					used_color_code.append(tax_color_code)
					used_tax_level[str(tax_level[0])]=tax_color_code
					used_tax_color_code[str(line_nb[3].split('.')[0])]=str(tax_level[0])+','+tax_color_code
				else:
					used_tax_color_code[str(line_nb[3].split('.')[0])]=str(tax_level[0])+','+str(used_tax_level[str(tax_level[0])])
			print('use color code => ',used_color_code)

			for j in nb_l:
				#for 
				if prefix_change == 'True' and line_nb[0] == mark_ID:
					#print(line_nb[0])
					q_prefix='n.' #query prefix after match the ID condition

				try:
					#print(line_nb[0],cluster_dict[str(j)])
					q_list.append(q_prefix+str(q_label)+'\t'+line_nb[0])
					q_list2.append(q_prefix+str(q_label)+','+line_nb[1]+','+line_nb[0].split('_')[1]+','+line_nb[0].split('_')[0]+','+line_nb[3]+','+used_tax_color_code[str(line_nb[3].split('.')[0])])

					nb_cluster.append(q_prefix+str(q_label)+','+cluster_dict[str(j)])
					
				except KeyError:

					print(j,"not found in cluster!")

			q_label+=1
					
	nb_cluster=((set(nb_cluster)))
	q_list=((set(q_list)))
	q_list2=((set(q_list2)))

	w2label=open('query_label.out','w')
	for n in q_list:
		w2label.write(n+'\n')
	w2label.close()

	w2label=open('mapping.q','w')
	for n in q_list2:
		w2label.write(n+'\n')
	w2label.close()

	w2file=open(out_file,'w')
	for n in nb_cluster:
		w2file.write(n+'\n')
	w2file.close()

#usage: remove_seq('NZ_CP021812','test_dup.fasta','out.fasta',1)	
def remove_seq(gene_label,file_input,file_output,num_del):
	fileopen=open(file_input,'r')
	fileread=fileopen.read().split('>')
	fileopen.close()
	writeoutput=open(file_output,'w')
	count_del=0
	for i in fileread:
		if i !='':			
			passport=True				
			k=i.split('\n')
			if gene_label == k[0].split()[0]:
				passport=False
				count_del+=1
			#print i[0]
			if count_del > num_del:
				passport = True
			#print passport,count_del
			if passport == True:
				writeoutput.write('>'+i)
	writeoutput.close()


#check gene label duplicate, return duplicate status (True/False) and list of the duplicate sequences
def check_duplication_organisms(inputfile):
	print(inputfile)
	cmd = 'grep ">" '+inputfile+'|sort|uniq -c '
	
	ps = Popen(cmd,shell=True,stdin=PIPE, stdout=PIPE, stderr=STDOUT, close_fds=True,encoding='utf8')
	output = ps.stdout.read()
	list_duplicate=[]
	output=output.split('\n')
	duplicate=False
	for i in output:
		i=i.split()
		if len(i)>1:
			if int(i[0])>1:
				print("Duplication found at sequence",i[1])
				list_duplicate.append([i[1],i[0]]) #name of duplicate seq,number of duplicated found
				duplicate=True

	return duplicate,list_duplicate

#remove_duplication_seq('test_dup.fasta','out.fasta')
#check duplicate header of fasta sequences
def remove_duplication_seq(file_input,out_file):
	print('Start remove duplicate sequence by checking header...')
	duplicate_check= check_duplication_organisms(file_input)
	if duplicate_check[0] == True: #means duplication found
		print('Found duplicate sequence !')
		#run remove duplicate sequence
		num_remove=0
		shutil.copy2(file_input,'remove_'+str(num_remove)+'.temp')

		for i in duplicate_check[1]:
			if num_remove>0:
				shutil.copy2('out_'+str(num_remove-1)+'.temp','remove_'+str(num_remove)+'.temp')
			#i[0] = name of duplicate seq, i[1]=number of duplicated found
			#print(i[0])
			remove_seq(i[0].replace('>',''),'remove_'+str(num_remove)+'.temp','out_'+str(num_remove)+'.temp',int(i[1])-1)
			print('Removed!!')
			num_remove+=1
		shutil.copy2('out_'+str(num_remove-1)+'.temp',out_file)	
		os.system('rm remove_*.temp out_*.temp')
	else:
		print('No duplicate sequence !')
		os.system('cp '+file_input+' '+out_file)
	print('Complete!')

#do multiple sequence alignment and convert the output to phylip format
def make_multiple_seq_align(multi_fasta_file):
	print('Start multiple sequence alignment ...')
	file_name=(os.path.splitext(os.path.basename(multi_fasta_file))[0])
	cmdline = MuscleCommandline(input=multi_fasta_file, out=file_name+".aln", clw=True)
	cmdline()
	AlignIO.convert(file_name+".aln", "clustal", file_name+".phy", "phylip-relaxed")
	print('Complete!')

#do multiple sequence alignment and convert the output to phylip format
def make_MAFFT_multiple_seq_align(multi_fasta_file):
	print('Start multiple sequence alignment ...')
	file_name=(os.path.splitext(os.path.basename(multi_fasta_file))[0])
	cmdline = MuscleCommandline(input=multi_fasta_file, out=file_name+".aln", clw=True)
	cmdline()
	AlignIO.convert(file_name+".aln", "clustal", file_name+".phy", "phylip-relaxed")
	print('Complete!')

def make_phylo_tree(phylip,export_newick):
	print('Start calculate pairwise distance metric and sum of branch lenght ...')
	aln = AlignIO.read(open(phylip), 'phylip-relaxed')
	calculator = DistanceCalculator('blosum62')
	dm = calculator.get_distance(aln)
	#print(dm) ##########################################
	constructor = DistanceTreeConstructor()
	tree = constructor.nj(dm)
	#print (tree) #for visualization #########################################
	#Phylo.draw(tree, branch_labels=lambda c: c.branch_length) #need pylab and matplotlib

	if export_newick == 'T':
		file_name=(os.path.splitext(os.path.basename(phylip))[0])
		Phylo.write(tree , file_name+'.nw', 'newick')

	print('Complete!')
	return tree.total_branch_length()

#make_phylo_tree('16s_u.phy','test.nw')

def make_phylo_fasttree(phylip,export_newick):
	print('Start FastTree ...')
	cmd='FastTreeMP -gtr -nt '+str(phylip)+' > '+str(export_newick)
	ps=Popen(cmd,shell=True,stdin=PIPE, stdout=PIPE, stderr=STDOUT, close_fds=True,encoding='utf8')
	psout = ps.stdout.read()
	print('Done!')	

#make_phylo_fasttree('16s_u.phy','test.nw')


#to convert synteny table to SQLite database, to make it faster to access
#warning: should remove duplicate sequences (sRNA) before run this method
def synteny2DB(synteny_file,cluster_file,srRNA_file):
	#make list of neighboring labeled with cluster id
	count=1	
	cluster_list=[]
	for clus in open(cluster_file):
		clus = clus.rstrip()
		if clus != 'x':
			col=clus.split()
			nb=col[1].split(',')
			for i in nb:
				#print(cluster_list)
				if [str(count),i] not in cluster_list:
					cluster_list.append([str(count),i])
			count+=1

	#print(cluster_list)
	synteny_list=[]

	for genome in open(synteny_file):
		genome = genome.rstrip()
		if 'ID	organism	accesion' not in genome:
			col=genome.split('\t')
			accesion=col[0].split('_')[0] #genome accession
			synteny=col[4].split(',')
			for i in synteny:
				synteny_list.append([str(accesion),i])

	#print(synteny_list) ####################

	fasta_list=[]
	read_file=open(srRNA_file,'r')
	read_a=read_file.read()
	read_a=read_a.split('>')

	for fasta in read_a:
		if fasta != '':
			line_fasta = fasta.split('\n')
			acc=line_fasta[0]
			seq=line_fasta[1]
			
			fasta_list.append([str(acc),seq])
	#print(fasta_list)


	conn = sqlite3.connect("synteny.db")
	c = conn.cursor()
	#c.execute("DROP TABLE neighbor_conservation")

	#table for genes labeled with cluster ID
	c.execute("CREATE TABLE cluster (cluster_id INTEGER NOT NULL, genes TEXT NOT NULL, PRIMARY KEY (genes) )")
	c.execute("CREATE TABLE r16s (genome_acc TEXT NOT NULL, sequence TEXT NOT NULL, PRIMARY KEY (genome_acc) )")
	c.execute("CREATE TABLE synteny (genome_acc TEXT NOT NULL, genes TEXT NOT NULL, FOREIGN KEY(genome_acc) REFERENCES r16s (genome_acc), FOREIGN KEY(genes) REFERENCES cluster (genes))") #no primary key

	c.executemany("INSERT INTO cluster VALUES (?, ?)", cluster_list)
	c.executemany("INSERT INTO synteny VALUES (?, ?)", synteny_list)
	c.executemany("INSERT INTO r16s VALUES (?, ?)", fasta_list)

	c.execute("CREATE INDEX idx1 ON synteny(genome_acc, genes)")
	conn.commit()
	conn.close()


#to calculate Phylo score for each cluster using syneny_db as input, cut_off is minimum number of genomes for the neighborhood conservation
def calculate_Phylo_score(syneny_db,cut_off,weight_score): #ignoring weight_score by setting it to zero

	min_score=0.001
	conn = sqlite3.connect(syneny_db)
	c = conn.cursor()

	c.execute("SELECT DISTINCT cluster_id FROM cluster")
	result1 = c.fetchall()

	w2score=open('Phylo_score.tab','w')

	for c_id in result1:
		phylo=0
		print("cluster number >> "+str(c_id[0]))

		#retrieve 16s rRNA from database , 1 genes per genome(not count paralog) 
		c.execute("SELECT DISTINCT cluster_id, r16s.genome_acc, r16s.sequence FROM cluster, r16s, synteny WHERE synteny.genes=cluster.genes AND r16s.genome_acc=synteny.genome_acc AND cluster.cluster_id="+str(c_id[0]))
		result2 = c.fetchall()

		#print(result2) #####################
		
		#make 16s rRNAs fasta file	
		sequence16s=''
		count_seq=0
		for k in result2:
			sequence16s+='>'+k[1]+'\n'+k[2]+'\n'

			count_seq+=1
		#print(sequence16s)####################
		#print(c_id,result2)

		pass_num_org=False
		if count_seq >= cut_off:
			pass_num_org=True
			w2fasta=open('16sRNA_fasta.temp','w')
			w2fasta.write(sequence16s)	
			w2fasta.close()

			make_multiple_seq_align("16sRNA_fasta.temp")
			phylo=make_phylo_tree("16sRNA_fasta.phy",'F')
			print(phylo) ##########################

			if phylo == 0 : #means the 16sRNAs are identical, so do counting genomes for Phylo score
				phylo=count_seq* min_score #0.001 is weight score for each genome

		#Phylo_score_equation=(float(weight_score)/10.0)+float(phylo) #consider all of gene neighborhoods
		#Phylo_score_equation=0
		if phylo > 0.0:
			Phylo_score_equation=(float(weight_score)/10.0)+float(phylo) #consider only of gene neighborhoods that are conserved more than cutoff (3 genomes)
			#Phylo_score_equation=(1.0)+(float(weight_score)*float(phylo)) #consider only of gene neighborhoods that are conserved more than cutoff (3 genomes)
			w2score.write('c.'+str(c_id[0])+'\t'+str(Phylo_score_equation)+'\n')	
		else:
			#print('>>>>>>>>>>>>>>>',count_seq) ########################################################################
			if count_seq == 2:
				Phylo_score_equation= 2*min_score
				w2score.write('c.'+str(c_id[0])+'\t'+str(Phylo_score_equation)+'\n')
			elif count_seq == 1:
				Phylo_score_equation= 1*min_score
				w2score.write('c.'+str(c_id[0])+'\t'+str(Phylo_score_equation)+'\n')
		if count_seq == 0:

			print('No 16s rRNA found of ',c_id)
	w2score.close()

	conn.close()	


def convert_node2edge_weight(node_interaction_file,node_weight_file,outfile):
	weight_dict={}
	for j in open(node_weight_file):
		j=j.rstrip()
		j=j.split('\t')	
		weight_dict[j[0]] = j[1]	
	w2f=open(outfile,'w')
	for i in open(node_interaction_file):
		i=i.rstrip()
		i=i.split(',')

		try:
			if float(weight_dict[i[1]])>0:
				#print(i[0]+','+i[1]+','+str(5+float(weight_dict[i[1]])))
				w2f.write(i[0]+','+i[1]+','+str(float(weight_dict[i[1]]))+'\n')
		except KeyError:
			print('No cluster '+i[1])
		
	w2f.close()

def remove_first_seq(fasta,outfile): #multifasta file as input (use sRNA sequences) , remove first sequence (query in Glassgo) which was retreive from GLASSgo
	out_file=open(outfile,'w')
	print('Remove first sequence as GLASSgo query!')
	i=1
	for seq_rec in SeqIO.parse(fasta,"fasta"):
		if i >= 2: #Remove first sequence as GLASSgo query
			out_file.write('>'+str(seq_rec.id)+'\n'+str(seq_rec.seq)+'\n')
		i+=1
	out_file.close()

def pairwise_ali(fasta,outfile): #multifasta file as input (use sRNA sequences)
	from Bio import pairwise2, Align, AlignIO
	out_file=open(outfile,'w')

	seq_dict={}
	key=[]
	for seq_rec in SeqIO.parse(fasta,"fasta"):
		seq_dict[seq_rec.id]=seq_rec.seq
		key.append(seq_rec.id)

	combos = itertools.combinations(key, 2) #make combinations of the sequences
	for k,v in combos:

		aln = pairwise2.align.globalxx(seq_dict[k],seq_dict[v])
		seq_ident=aln[0][2]
		seq_len=aln[0][4]+1
		p_ident=seq_ident/float(seq_len)

		#print(k+'\t'+v+'\t'+str(p_ident))
		#print('ident',seq_ident)
		#print('len',seq_len)
		#print('pident',p_ident)

		#print(aln)
		#print(pairwise2.format_alignment(*aln[0]))
		out_file.write(k+','+v+','+str(p_ident)+'\n')
	out_file.close()

def pairwise_ali_vsearch(fasta,outfile): #multifasta file as input (use sRNA sequences)
	cmd='vsearch --allpairs_global '+fasta+' --blast6out '+outfile+'.temp --acceptall'
	ps=Popen(cmd,shell=True,stdin=PIPE, stdout=PIPE, stderr=STDOUT, close_fds=True,encoding='utf8')
	psout = ps.stdout.read()
	print(psout)

	out_file=open(outfile,'w')
	for i in open(outfile+'.temp'):
		if i != '':
			i=i.rstrip()
			col=i.split()
			out_file.write(col[0]+','+col[1]+','+str(col[2])+'\n')
	out_file.close()

	cmd='rm '+outfile+'.temp'
	ps=Popen(cmd,shell=True,stdin=PIPE, stdout=PIPE, stderr=STDOUT, close_fds=True,encoding='utf8')
#pairwise_ali_vsearch('pass_glassgo2copra.fasta','pass_glassgo2copra.ali')
#pairwise_ali('pass_glassgo2copra.fasta','pass_glassgo2copra.ali_bio')

def convert_pairwise2weight(pairwise_outfile,query_label,weight_score,outfile): #query_label.out
	q_dict={}
	for j in open(query_label):
		j=j.rstrip()
		q=j.split()
		q_dict[q[1]]=q[0]

	w2f=open(outfile,'w')
	for i in open(pairwise_outfile):
		i=i.rstrip()
		col=i.split(',')
		#CP000002.3:1639887-1640096 AP006627.1:c2536187-2535964 to CP000002.3_1639887 AP006627.1_2536187
		query1=col[0].split(':')[0]+'_'+col[0].split(':')[1].split('-')[0].replace('c','')
		query2=col[1].split(':')[0]+'_'+col[1].split(':')[1].split('-')[0].replace('c','')
		#print(query1,query2)
		#print(q_dict[query1])
		#print(q_dict[query2])

		weight_equation=(float(weight_score)/10.0)+float(col[2])
		#weight_equation=(1.0)+(float(weight_score)*float(col[2])) #equ 1
		w2f.write(q_dict[query1]+','+q_dict[query2]+','+str(weight_equation)+'\n')
	w2f.close()

def map_fasta_header(fasta,query_label,outfile):
	
	q_dict={}
	for j in open(query_label):
		j=j.rstrip()
		q=j.split()
		q_dict[q[1]]=q[0]

	out_file=open(outfile,'w')
	name_file=open('interchange_header.temp','w')
	for seq_rec in SeqIO.parse(fasta,"fasta"):
		header_ori=str(seq_rec.id).split(':')[0]+'_'+str(seq_rec.id).split(':')[1].split('-')[0].replace('c','')
		changed_header=q_dict[header_ori]	
		name_file.write(str(changed_header)+'\t'+str(seq_rec.description)+'\n')
		out_file.write('>'+str(changed_header)+'\n'+str(seq_rec.seq)+'\n')
	out_file.close()
	name_file.close()
#map_fasta_header('pass_glassgo2copra.fasta','query_label.out','change.fasta')

def map_back_fasta_header(fasta,interchange_header,outfile):
	#map outputfile after GA optimization to the same header as before
	q_dict={}
	for j in open(interchange_header):
		j=j.rstrip()
		q=j.split('\t')
		q_dict[q[0]]=q[1]

	out_file=open(outfile,'w')

	for seq_rec in SeqIO.parse(fasta,"fasta"):
		header_ori=str(seq_rec.id)
		changed_header=q_dict[header_ori]	
		out_file.write('>'+str(changed_header)+'\n'+str(seq_rec.seq)+'\n')
	out_file.close()

#map_back_fasta_header('optimized.fasta','interchange_header.temp','change.fasta')

def select_fasta_header(fasta,outfile,list_remove):
	
	out_file=open(outfile,'w')
	for seq_rec in SeqIO.parse(fasta,"fasta"):
		header=str(seq_rec.description)
		if header not in list_remove:			
			out_file.write('>'+str(header)+'\n'+str(seq_rec.seq)+'\n')
	out_file.close()

def calculate_pairwise_network_similarity(network_file,output): #three columns file [q, c, weight_score]
	print('Calculate pairwise network similarity...')

	Q_C={}
	list_Q_C=[]
	uniq_Q=[]

	for i in open(network_file):
		i=i.rstrip()
		if 'c.' in i :
			col=i.split(',')
			recol=[]

			#in the case q. is in second column
			if 'q.' in col[0]: #make list of Query 
				uniq_Q.append(col[0])
				list_Q_C.append(col)
				Q_C[col[0],col[1]]=col[2] #make dict of Q - C relationship

			elif 'q.' in col[1]:
				uniq_Q.append(col[1])
				list_Q_C.append([col[1], col[0], col[2]])
				Q_C[col[1],col[0]]=col[2] #make dict of Q - C relationship


	uniq_Q=set(uniq_Q)
	#print(Q_C)
	#print(uniq_Q)

	dict_Q_C={} #{'q.1': , ('c.2', 'c.5'),
	sum_Q={} #sum score of c.* specific to q.
	total_Q={} #all c.* specific to q.

	for match in uniq_Q: #match => q.
		sum_score=0
		temp_list_c=[]
		for match_C in list_Q_C:
			
			if (match == match_C[0]) :
				#print(match,match_C)
				sum_score+=float(match_C[2])
				sum_Q[match]=sum_score
				temp_list_c.append(match_C[1])

		total_Q[match]=temp_list_c
	#print(sum_Q)
		#print(match,sum_score)
	w2file=open(output,'w')
	combos = itertools.combinations(uniq_Q, 2) #make combinations of the sequences
	for k,v in combos:
		#print(k,v)
		comb_list_QC = total_Q[k] + total_Q[v]
		#print(comb_list_QC)
		#print(Counter(comb_list_QC))
		count_QC=Counter(comb_list_QC)
		#print(count_QC)
		sum_Q_i=sum_Q[k]+sum_Q[v]
		sum_overlap=0
		for i in count_QC:
			if count_QC[i] >= 2:
				#print('More than two ',i)
				#print('score',k,i,Q_C[(k,i)])
				sum_overlap+=float(Q_C[(k,i)])

				#print('score',v,i,Q_C[(v,i)])
				sum_overlap+=float(Q_C[(v,i)])

			else:
				sum_overlap+=0

		#print(k,v,sum_overlap,sum_Q_i,sum_overlap/sum_Q_i)
		w2file.write(k+','+v+','+str(sum_overlap/sum_Q_i)+'\n') #q node, c node , overlap score between q / sum score of q
	w2file.close()
	print('Done!!')

#Usage: calculate_pairwise_network_similarity('weigth_edg.tab','out_network.csv')

def combine_weight(file1,file2,output): #combine weight from two network file if they contain the same node relationship
	from scipy.stats.mstats import gmean
	#use average value as combination method

	#check unique relationships

	file1_dict={}
	f1_pass='F'
	for f1 in open(file1):
		f1=f1.rstrip()
		f1=f1.split(',')
		if f1 != '':
			if ((f1[0],f1[1]) in file1_dict) or ((f1[1],f1[0]) in file1_dict):
				print('Your file 1 ',file1,'contains duplicate relationship! ',(f1[0],f1[1]),' Please remove.')
				break
			else:
				file1_dict[(f1[0],f1[1])]=f1[2]
				f1_pass='T'
	#print(file1_dict)

	if f1_pass=='T' :

		w2file=open(output,'w')
		file2_list=[]
		count_non=0
		count_yes=0
		count_all=0
		f2_pass='F'
		for f2 in open(file2):
			count_all+=1
			f2=f2.rstrip()
			f2=f2.split(',')
			if f2 != '':
				if ([f2[0],f2[1]] in file2_list) or ([f2[1],f2[0]] in file2_list):
					print('Your file 2 ',file2,'contains duplicate relationship! ',(f2[0],f2[1]),' Please remove.')
					f2_pass='F'
					break
				else:
					f2_pass='T'
					
					if (f2[0],f2[1]) in file1_dict: 
						count_yes+=1
						score_f1 = float(file1_dict[(f2[0],f2[1])])
						del file1_dict[(f2[0],f2[1])] #remove already matched key
						relation=f2[0]+','+f2[1]
						file2_list.append([f2[0],f2[1]])
					elif (f2[1],f2[0]) in file1_dict: 
						score_f1= float(file1_dict[(f2[1],f2[0])])
						del file1_dict[(f2[1],f2[0])]
						count_yes+=1
						relation=f2[1]+','+f2[0]
						file2_list.append([f2[1],f2[0]])
					else:
						count_non+=1
						score_f1=0.0
						relation=f2[1]+','+f2[0]
						file2_list.append([f2[1],f2[0]])
						file2_list.append([f2[0],f2[1]])
						#print('No key found! for', (f2[1],f2[0]), 'in file 2. This score of this relation will be used direcly without combination.')							

	
					score_f2= float(f2[2])
					combined_score= (score_f1+score_f2)/2 #arithmetic mean
					#combined_score=  hmean([score_f1, score_f2]) #hamonic mean
					#combined_score=  gmean([score_f1, score_f2]) #geometric mean
					w2file.write(relation+','+str(combined_score)+'\n')
					

		count_file1=0
		if (len(file1_dict) > 0) and (f2_pass=='T'): #to check unmatched relationship in file 1
			for i in file1_dict : 
				#print('not match>>',i)
				#print('No key found! for', i, ' in file 1. This score of this relation will be used direcly without combination.')
				w2file.write(i[0]+','+i[1]+','+str(file1_dict[i])+'\n')
				count_file1+=1

		w2file.close()
		print('Matched relationship >',count_yes)
		print('Unmatched relationship file1 >',count_file1)
		print('Unmatched relationship file2>',count_non)
		print('All relationship in file2 >',count_all)
		print('Done!!')

#combine_weight('pairwise_sim.csv','pairwise_sim2.csv','pairwise_sim3.csv')


def build_phylo_tree_from_similarity_file(file_name_pair_dist, tree_output, Remove_query, list_quey_for_remove): #to return total branch lenght
	file_pair_dist=file_name_pair_dist	#all.reciprocal

	cmd_neighbor = "cut -f1,2,3 -d ',' "+file_pair_dist+" "
	ps=Popen(cmd_neighbor,shell=True,stdin=PIPE, stdout=PIPE, stderr=STDOUT, close_fds=True,encoding='utf8')
	pair_dist = ps.stdout.read()
	pair_dist = pair_dist.split('\n')
	#print(pair_dist)
	if '' in pair_dist:
		pair_dist.remove('')

	cmd_neighbor = "awk -F',' '{print $1}{print $2}' "+file_pair_dist+" |sort -g|uniq"
	ps=Popen(cmd_neighbor,shell=True,stdin=PIPE, stdout=PIPE, stderr=STDOUT, close_fds=True,encoding='utf8')
	list_genome = ps.stdout.read()
	list_genome = list_genome.split('\n')
	#print(list_genome)
	if '' in list_genome:
		list_genome.remove('')

	#print 'Total genomes >> ',len(list_genome)
	Total_genomes= len(list_genome)
	#print 'Total pair distance >> ',(len(list_genome)*(len(list_genome)-1))/2
	Total_pair_distance=(len(list_genome)*(len(list_genome)-1))/2
	check1=False
	#print(len(pair_dist), Total_pair_distance)
	if len(pair_dist) == Total_pair_distance : #To check the number of pair distance
		#print 'Pass check 1 : total pair distances are correctly found '
		check1=True
	else:
		print('Warning: Number of pairwise distance is not equal to the number of genome!!')

	#remove option: optional
	if Remove_query == True and list_quey_for_remove !=[] :
		for rev in list_quey_for_remove:
			count_pair_dis=0
			for col in pair_dist:
				col=col.split(',')
				#print(col)
				if col[0] != 'Removed':
					if rev == col[0] or rev == col[1]:
						pair_dist[count_pair_dis]='Removed'
						#print(rev,col)

				count_pair_dis+=1

			count_genome=0
			for col in list_genome:
				#print(col)
				if col != 'Removed':
					if rev == col :
						list_genome[count_genome]='Removed'
				count_genome+=1

		pair_dist[:]= (x for x in pair_dist if x != 'Removed')
		list_genome[:]= (x for x in list_genome if x != 'Removed')
		#print(pair_dist)
		#print(list_genome)	
			
	matrix =[]
	for n in range(1,len(list_genome)+1 ):
		matrix.append([0]*n)
	#print matrix
	Total_metrix=len(matrix)
	#print 'Total matrix >>',len(matrix)

	Ds=_DistanceMatrix(list_genome,matrix)

	for pair in pair_dist:
		i=pair.split(',')
		#print(i)
		Ds[i[0],i[1]] = (1.0-float(i[2])) #change simililarity score to dis-similarity score
	#print Ds
	constructor = DistanceTreeConstructor()
	tree = constructor.nj(Ds)
	#print(tree) #for visualization
	#Phylo.draw(tree, branch_labels=lambda c: c.branch_length)

	Phylo.write(tree , tree_output+'.nw', 'newick')
	#Phylo.draw_ascii(tree)

	#print('total_branch_length >> '+str(tree.total_branch_length()))
	return Total_genomes, Total_pair_distance, check1, tree.total_branch_length()

def mylayout(node):
	code2name = {}
	for i in open('query_label.out'):
		i=i.rstrip()
		col=i.split('\t')
		code2name[col[0]]=col[1]

	if node.is_leaf():
		faces.add_face_to_node(AttrFace("name"), node, column=0)
		longNameFace = faces.TextFace(code2name[node.name])
		faces.add_face_to_node(longNameFace, node, column=0)

def make_pc_tree(newick_file,outfile):
	sptree = PhyloTree(newick_file, format=1)
	ts = TreeStyle()
	ts.layout_fn = mylayout
	ts.show_leaf_name = False
	ts.mode = "c"
	ts.arc_start = -180 # 0 degrees = 3 o'clock
	ts.arc_span = 180

	#print(sptree.get_ascii(attributes=["name", "species"]))
	sptree.render(outfile+".png", w=1200, tree_style=ts)


def compare_tree(tree1,tree2): #tree in newick format
	#t1 = Tree(tree1, format=1)
	#t2 = Tree(tree2, format=1)

	#t1 = Tree('(((a,b),c), ((e, f), g));')
	#t2 = Tree('(((a,c),b), (g, H));')
	#print(t1.robinson_foulds(t2))
	#rf, max_rf, common_attrs,parts_t1, parts_t2, discarded_edges_t1, discarded_edges_t2 = t1.robinson_foulds(t2)

	t1 = Tree(tree1, format=1)
	t2 = Tree(tree2, format=1)

	rf, max_rf, common_attrs,parts_t1, parts_t2, discarded_edges_t1, discarded_edges_t2 = t1.robinson_foulds(t2,unrooted_trees=True)
	#rf, max_rf = t1.robinson_foulds(t2,unrooted_trees=True)
	print(t1, t2)
	nRF=float(rf)/max_rf#Normalized Robinson-Foulds distance (RF/maxRF)
	print("RF distance is %s over a total of %s" %(rf, max_rf))
	print("Normalized Robinson-Foulds distance (RF/maxRF) = %s" %(nRF))
	#print("Partitions in tree2 that were not found in tree1:", parts_t1 - parts_t2)
	#print("Partitions in tree1 that were not found in tree2:", parts_t2 - parts_t1)
	return nRF

#compare_tree('./test.nw','./test.nw')


def create_code_chromosome(label_file): #label file , read the first column
	chom=[]
	for i in open(label_file):
		i=i.rstrip()
		col=i.split('\t')
		chom.append(col[0])
	chom=set(chom)
	N_genes=len(chom)
	print("Number of genes =>",N_genes)
	print("Original chromosome =>",chom)

	return N_genes, list(chom)

def uncoding_chromosome(individual,chom): #input is binary code and original label, and return label code
	list_remove_gene=[]
	if len(individual) == len(chom):
		
		count_i=0
		for i in individual:
			#print(count_i)
			if i == 0:
				#print('Gene',count_i, 'is removed.')
				list_remove_gene.append(chom[count_i])
			count_i+=1
	else:
		print("Number of genes in in coded chromosome and uncoded chromosome is not equal!")
	print('Removed genes =>',list_remove_gene)
	return list_remove_gene


def evalOneMax(individual):
    return sum(individual)

def evalOneMin_3score(original_label,individual):

	FASTA_input1='pairwise2weight.csv'	#similarity relationship 
	FASTA_input2='GNSN.csv'	#similarity relationship 
	FASTA_input3='renamed_glassgo_out.temp'	#multiple fasta for multiple sequence alignment

	removed_label= uncoding_chromosome(individual,original_label) #return list of removed queries
	print('Remove =>',removed_label)

	### calculate phylo tree from pairwise sequence similarity file
	build_phylo_tree_from_similarity_file(FASTA_input1, FASTA_input1, True, removed_label)
	#print(make_pc_tree(FASTA_input1+'.nw',FASTA_input1))

	### calculate phylo tree from pairwise GNN similarity file
	build_phylo_tree_from_similarity_file(FASTA_input2, FASTA_input2, True, removed_label)
	#print(make_pc_tree(FASTA_input2+'.nw',FASTA_input2))

	### calculate phylo tree from multiple sequence alignment file (conserved structure)
	Fasta3_file='selected_'+FASTA_input3.split('.')[0]
	select_fasta_header(FASTA_input3,Fasta3_file+'.temp',removed_label) #remove sequences
	make_multiple_seq_align(Fasta3_file+'.temp')
	#print(Fasta3_file)
	make_phylo_fasttree(Fasta3_file+'.phy',Fasta3_file+'.nw') #return nw tree
	#print(make_pc_tree(Fasta3_file+'.nw',FASTA_input3))

	RFscore1_2=compare_tree(FASTA_input1+'.nw',FASTA_input2+'.nw')
	RFscore1_3=compare_tree(FASTA_input1+'.nw',Fasta3_file+'.nw')
	RFscore2_3=compare_tree(FASTA_input2+'.nw',Fasta3_file+'.nw')

	sum_RF=RFscore1_2+RFscore1_3+RFscore2_3
	ave_RFscore=sum_RF/3.0

	print('Average Robinson-Foulds distance =>' ,ave_RFscore)

	return ave_RFscore
#evalOneMin_3score(['q.1','q.2','q.3','q.4','q.18'],[1,1,1,1,0])

def evalOneMin(original_label,individual):
	FASTA_input1='pairwise2weight.csv'
	FASTA_input2='GNSN.csv'

	removed_label= uncoding_chromosome(individual,original_label) #return list of removed queries
	print('Remove =>',removed_label)

	build_phylo_tree_from_similarity_file(FASTA_input1, FASTA_input1, True, removed_label)
	print(make_pc_tree(FASTA_input1+'.nw',FASTA_input1))

	build_phylo_tree_from_similarity_file(FASTA_input2, FASTA_input2, True, removed_label)
	print(make_pc_tree(FASTA_input2+'.nw',FASTA_input2))

	RFscore=compare_tree(FASTA_input1+'.nw',FASTA_input2+'.nw')

	return RFscore

def fitness_max_min(original_label,individual):
	#print(individual,original_label)

	return evalOneMax(individual), evalOneMin_3score(original_label,individual),

def GA_tree(NGEN,NPOP,FASTA_input) : #number of generation, number of individual in population, number of gene in individual chromosome
	map_fasta_header(FASTA_input,'query_label.out','renamed_glassgo_out.temp') #for multiple seq alignment

	original_chro=create_code_chromosome('query_label.out') #return total number of genes and label set
	Nind=original_chro[0]
	creator.create("FitnessMax", base.Fitness, weights=(10.0, -1.0))
	creator.create("Individual", list, fitness=creator.FitnessMax)

	toolbox = base.Toolbox()

	toolbox.register("attr_bool", random.randint, 1, 1)
	toolbox.register("individual", tools.initRepeat, creator.Individual, toolbox.attr_bool, n=Nind)
	toolbox.register("population", tools.initRepeat, list, toolbox.individual)

	toolbox.register("evaluate", fitness_max_min,original_chro[1]) #sent to evaluation: label set is in position 1, individual chromosome is in position 2
	toolbox.register("mate", tools.cxTwoPoint)
	toolbox.register("mutate", tools.mutFlipBit, indpb=0.1)
	toolbox.register("select", tools.selNSGA2)

	population = toolbox.population(n=NPOP)

	w2file=open('GLASSgo_optimization.out','w')
	w2file.write('#generations\tAve_N_homologs\tAve_distance\n')
	w2file.close()

	store_chromosomes={}
	for gen in range(NGEN):
		print('Generation ',gen)
		offspring = algorithms.varAnd(population, toolbox, cxpb=0.5, mutpb=0.2)
		fit_ind = []
		for k in offspring:
			if str(k) not in store_chromosomes:
				#print('not found',k)
				fit_ind.append(toolbox.evaluate(k))
				store_chromosomes[str(k)]=toolbox.evaluate(k)
			else:
				#print('found',k)
				fit_ind.append(store_chromosomes[str(k)])

		#print(fit_ind)
		list_fit_1=[]
		list_fit_2=[]
		for fit, ind in zip(fit_ind, offspring):		
			ind.fitness.values = fit
			list_fit_1.append(fit[0])
			list_fit_2.append(fit[1])

		ave_fit1=numpy.mean(list_fit_1)
		ave_fit2=numpy.mean(list_fit_2)
		print('Average score 1 => ',ave_fit1)
		print('Average score 2 => ',ave_fit2)
		print('Original label =>', original_chro[1])
		#print('Best chromosome =>',tools.selBest(population, k=1))

		w2file=open('GLASSgo_optimization.out','a')
		w2file.write(str(gen)+'\t'+str(ave_fit1)+'\t'+str(ave_fit2)+'\n')
		w2file.close()

		population = toolbox.select(offspring, k=len(population))
		#print(population)
	top10 = tools.selBest(population, k=1)

	w2file=open('GLASSgo_optimization.out','a')
	w2file.write('#Original label =>'+str(original_chro[1]))
	w2file.close()

	w2file=open('Dict_GLASSgo_optimization.out','w')
	best_score=0
	best_chromosome=''
	for i in store_chromosomes:
		score=store_chromosomes[i]
		w2file.write(i+'\t'+str(score[0])+'\t'+str(score[1])+'\n')
		#print(store_chromosomes[i])
	w2file.close()

	print('Best cromosome from the last genn',top10)
	final_removed_label=uncoding_chromosome(top10[0],original_chro[1])
	select_fasta_header('renamed_glassgo_out.temp','optimized.fasta',final_removed_label) #remove sequences
	map_back_fasta_header('optimized.fasta','interchange_header.temp','final_optimized.fasta')
	os.system('rm *.temp')

def randomwalk_optimization(input_fasta):
	#need to run glassgo post process modi before
	#map_fasta_header(input_fasta,'query_label.out','renamed_glassgo_out.temp')
	#call('R --slave -f ./scripts/make_weighted_network_RW.R --args workdir=./ start=q.2',shell=True)

	select_fasta_header('renamed_glassgo_out.temp','optimized.fasta',['q.106','q.177','q.80','q.110','q.47','q.77','q.70','q.140','q.169','q.72','q.79','q.128','q.56','q.57','q.59','q.65','q.67','q.61','q.45','q.58','q.126','q.179','q.74','q.129','q.130','q.178','q.197','q.51','q.63','q.66'])
	map_back_fasta_header('optimized.fasta','interchange_header.temp','final_optimized_RW.fasta')
#randomwalk_optimization('pass_glassgo2copra.fasta')


#########################################################################################
################################### End of methods ######################################
#########################################################################################


#########################################################################################
####################################### Pipelines #######################################
#########################################################################################

############################# Pipeline to calculate Phylo score ##################################################
#affter run glassgo_potprocessing_apivat.r (for creating synteny files)

#remove_duplication_seq("16s.fasta","16s_u.fasta")
#synteny2DB('testfile_synteny_table.txt','testfile_cluster_table.txt','16s_u.fasta')
#print(test_db())
#make_multiple_seq_align("16s_u.fasta")
#make_phylo_tree("16s_u.phy",'F')

#calculate_Phylo_score("synteny.db",3,10) #database name , number of conserved genomes cutoff, weight score

################################################################################################################
#convert_node2edge_weight('nb_conserved.out','Phylo_score.tab','node2edge.csv') #neighbor relationship file, Phylo score file, output file

### for calculating pairwise similarity score between query sequences ###
#pairwise_ali("./INPUT/RF02376.fasta","pairwise2.csv")
#convert_pairwise2weight("pairwise2.csv","query_label.out",10,"pairwise2weight.csv") #output from alignment, weight score, query_label file, output

#remove_duplication_seq("./INPUT/RF02376.fasta","RF02376_u.fasta")

############################# Pipeline to calculate network strength ##################################################

def make_GNN_with_weight(input_file, neighborhood_weight, query_weight): #input , neighborhood_weight, query_weight

	### call genome neighborhood ###
	
	cmd_neighbor = 'R --slave -f  ./scripts/GLASSgo_postprocessing_7_modi.r --args filename='+input_file+' duplicates_allowed=TRUE synteny_window=5000  name=testfile coprarna_compatible=TRUE'
	ps=Popen(cmd_neighbor,shell=True,stdin=PIPE, stdout=PIPE, stderr=STDOUT, close_fds=True,encoding='utf8')
	output = ps.stdout.read()
	print(output)

	### calculate Phylo score and make weighted network ##
	remove_duplication_seq("16s.fasta","16s_u.fasta")
	os.system('rm synteny.db')
	synteny2DB('testfile_synteny_table.txt','testfile_cluster_table.txt','16s_u.fasta')
	make_multiple_seq_align("16s_u.fasta")
	make_phylo_tree("16s_u.phy",'F')
	calculate_Phylo_score("synteny.db",3,neighborhood_weight) #database name , number of conserved genomes cutoff, weight score for network relationship
	make_network_input('testfile_cluster_table.txt', 'testfile_synteny_table.txt', 'nb_test.out', 'False') #
	convert_node2edge_weight('nb_test.out','Phylo_score.tab','node2edge.csv') #neighbor relationship file, Phylo score file, output file ## for convert node weight to edge weight

	### for calculating pairwise similarity score between query sequences ###
	pairwise_ali_vsearch(input_file,"pairwise2.csv")
	convert_pairwise2weight("pairwise2.csv","query_label.out",query_weight,"pairwise2weight.csv") #output from alignment, weight score, query_label file, output

	### concat two network file (q-q network and q-c network) and make network
	#####################################################################
	cmd_mknetwork = 'cat pairwise2weight.csv node2edge.csv > con_network.csv ' #| R --slave -f make_weighted_network.R --args input_csv=con_network.csv
	ps_network=Popen(cmd_mknetwork,shell=True,stdin=PIPE, stdout=PIPE, stderr=STDOUT, close_fds=True,encoding='utf8')
	output = ps_network.stdout.read()
	print(output)
	#####################################################################

#make_GNN_with_weight('./INPUT/RF02376.fasta', 0.5, 30) #input , neighborhood_weight, query_weight

############################# Pipeline to disturb network #############################################################

def random_spy(spy_name,list_of_edge_value,W_q,W_c,score_q,score_c,uniq_q,uniq_c):	#make spy in file con_network.csv
	#spy_name='qx.0'	
	if spy_name == 'no_spy':
		N_rand_Q=0.0

	else:
		percent_rand_Q=random.uniform(0, 1) #random_number_of_Q_from_pool e.g. 0.75 = 75% of total number of Q
		N_rand_Q=int(len(uniq_q)*percent_rand_Q)+1
		if N_rand_Q > len(uniq_q):
			print('Over random limit',N_rand_Q)

		list_of_random_Q = random.sample(uniq_q, N_rand_Q)
		list_of_random_score_Q = random.sample(list_of_edge_value, N_rand_Q)

	out_rand=open('random_relationship.temp','w')
	if spy_name != 'no_spy':
		for ni in range(0,N_rand_Q):
			out_rand.write(spy_name+','+str(list_of_random_Q[ni])+','+str(list_of_random_score_Q[ni])+'\n')
	out_rand.close()

	#os.system('cat con_network.csv random_relationship.temp > con_network_w_spy.csv')

	cmd_mknetwork = 'cat con_network.csv random_relationship.temp > con_network_w_spy.csv | R --slave -f make_weighted_network.R --args input_csv=con_network_w_spy.csv'
	ps_network=Popen(cmd_mknetwork,shell=True,stdin=PIPE, stdout=PIPE, stderr=STDOUT, close_fds=True,encoding='utf8')
	output = ps_network.stdout.read()
	count_com=0
	count_true=0
	for j in open('community.out'):
		if j != '':
			j=j.rstrip()
			if 'q.' in j :
				count_true+=1
			count_com+=1

	os.system('rm community.out')
	#os.system('rm con_network_w_spy.csv')

	### combine spy to the network file 
	if float(N_rand_Q) != 0.0:
		ave_score=sum(list_of_random_score_Q)/float(N_rand_Q) ########
	else:
		ave_score=0.0

	w2file=open('result_community_add_spy.tab','a')
	w2file.write(str(round_n)+'\t'+spy_name+'\t'+str(len_q)+'\t'+str(len_c)+'\t'+str(N_rand_Q)+'\t'+str(ave_score)+'\t'+str(W_q)+'\t'+str(W_c)+'\t'+str(count_com)+'\t'+str(count_true)+'\n')
	w2file.close()

def disturb_network():
	########################################
	#### Weight value #### [[Q_Q,Q_C]]
	weight_value=[[300,10]]
	#weight_value=[[100,10],[200,10],[300,10],[400,10],[500,10],[600,10],[700,10],[800,10],[900,10],[1000,10],[1200,10]]
	#

	w2file=open('result_community_add_spy.tab','w')
	w2file.write('Round\tSpy\tNum_query\tNum_neighbor\tNum_random_q\tAve_score\tWeight_q\tWeight_c\tNum_community\tNum_true_community\n') #Num_true_community => number of cummunity that cantains at least 1 query.
	w2file.close()

	for round_X in weight_value:

		## weight value 
		W_q=round_X[0]
		W_c=round_X[1]

		make_GNN_with_weight('./INPUT/RF02376.fasta', W_c, W_q) #no weight = 0.0 [Cluster_neighbor weight, Query weight]

		Q_Q=[] #node relationship
		Q_C=[]

		#make list of relationship
		#con_network.csv : output file from GNN building
		for i in open('con_network.csv'):
			i=i.rstrip()
			col=i.split(',')
			if ('q.' in col[0]) and ('q.' in col[1]) :
				Q_Q.append(col)

			elif ('q.' in col[0]) and ('c.' in col[1]) :
				Q_C.append(col)

		#print([row[0] for row in Q_Q]) #make list of first column in list
		uniq_q=set([row[0] for row in Q_Q]) #unique query gene set
		uniq_c=set([row[1] for row in Q_C]) #unique neighbor cluster

		score_q=[float(row[2]) for row in Q_Q] #score list from query gene relationship
		score_c=[float(row[2]) for row in Q_C] #score list from query-neighborhood relationship
		len_q=len(uniq_q)
		len_c=len(uniq_c)

		print('Number of query genes =>',len_q) #number of unique query gene
		print('Number of neighbor cluster =>',len_c)  #number of unique neighbor cluster
		#print('number of query =>',len(Q_Q[0]))



		numrandom=101
		print('##################  Start random relationships for ',str(numrandom-1),'times.  ###################')

		###### run for 100 times  ###### 
		for round_n in range(0,numrandom):
			if round_n == 0:
				random_spy('no_spy',[],W_q,W_c,[],[],[],[])

			else:
				rand_Q_or_C=random.uniform(0, 1)

				#simulate small value of score Q_Q and C_Q relationship
				score_q=[1]*100
				#score_c=[1.3]*100

				if rand_Q_or_C >= 0.5:	###spy = 'Q' #query relationship
					random_spy('qx.0',score_q,W_q,W_c,score_q,score_c,uniq_q,uniq_c)

				else:		###spy = 'C' #neighbor relationship
					random_spy('cx.0',score_c,W_q,W_c,score_q,score_c,uniq_q,uniq_c)

		os.system('rm con_network.csv')


############################# Pipeline to combine pairwise GNN similarity to pairwise sequence similarity #############################
############################# using modified GLASSgo to collect homologous sequences ##################################################

def make_GNSN_with_weight(input_file, neighborhood_weight, query_weight): #GNSN: Genome neighborhood similarity network    #input ,neighborhood_weight, query_weight

	### call genome neighborhood ###
	
	#this version of GLASSgo_postprocessing excludes first input sequence
	#need to be duplicates_allowed=FALSE for normal run to create GLASSgo2Copra output
	cmd_neighbor = 'R --slave -f  ./scripts/GLASSgo_postprocessing_8_modi.r --args filename='+input_file+' duplicates_allowed=FALSE synteny_window=5000  name=testfile coprarna_compatible=FALSE ooi=NC_000911'
	ps=Popen(cmd_neighbor,shell=True,stdin=PIPE, stdout=PIPE, stderr=STDOUT, close_fds=True,encoding='utf8')
	output = ps.stdout.read()
	print(output)
	error=''
	if 'Error' in output:
		error+='Minor error was found in GLASSgo_postprocessing step'

	### calculate Phylo score and make weighted network ##
	remove_duplication_seq("16s_GenBank.fasta","16s_u.fasta")
	os.system('rm synteny.db')
	synteny2DB('testfile_synteny_table.txt','testfile_cluster_table.txt','16s_u.fasta')
	make_multiple_seq_align("16s_u.fasta")
	make_phylo_tree("16s_u.phy",'F')
	calculate_Phylo_score("synteny.db",3,neighborhood_weight) #database name , number of conserved genomes cutoff, weight score for network relationship
	make_network_input('testfile_cluster_table.txt', 'testfile_synteny_table.txt', 'nb_test.out', 'False') #
	convert_node2edge_weight('nb_test.out','Phylo_score.tab','Phylo_score_node2edge.csv') #neighbor relationship file, Phylo score file, output file ## for convert node weight to edge weight

	### for calculating pairwise similarity score between query sequences ###
	#remove_first_seq(input_file,input_file+'2') #first seq is query seq, in the case of normal version of GLASSgo , but not necessary for the modified version
	remove_duplication_seq("pass_glassgo2copra.fasta","u_pass_glassgo2copra.fasta")
	pairwise_ali_vsearch('u_pass_glassgo2copra.fasta',"pairwise2.csv") #pass_glassgo2copra.fasta is the fasta output file after Glassgo2copra
	#os.system('rm '+input_file+'2')
	convert_pairwise2weight("pairwise2.csv","query_label.out",query_weight,"pairwise2weight.csv") #output from alignment, weight score, query_label file, output

	#####################################################################
	#cmd_mknetwork = 'cat pairwise2weight.csv Phylo_score_node2edge.csv > con_network.csv ' #| R --slave -f make_weighted_network.R --args input_csv=con_network.csv
	#ps_network=Popen(cmd_mknetwork,shell=True,stdin=PIPE, stdout=PIPE, stderr=STDOUT, close_fds=True,encoding='utf8')
	#output = ps_network.stdout.read()
	#print(output)
	#####################################################################

	#make network file using pairwise GNN similarity score as weighted edges
	calculate_pairwise_network_similarity('Phylo_score_node2edge.csv','GNSN.csv')
	combine_weight('GNSN.csv','pairwise2weight.csv','pairwise_GNSN.csv') #combine weight score from two file as average score
	print(error)

	#os.system('rm full_tree.Rdata distances.Rdata testfile_16S_tree.pdf coor.Rdata testfile_cluster_table.txt testfile_synteny_table.txt 16s.fasta 16s_subset.fasta 16s_GenBank.fasta 16s_aligned2.fasta 16s_aligned.fasta')

#####################################################################################################################
############################# Pipeline to make phylogenetic tree from different methods #############################
#####################################################################################################################
def make_phylo_tree_GNN(input_file, neighborhood_weight, query_weight): #GNSN: Genome neighborhood similarity network    #input ,neighborhood_weight, query_weight

	### call genome neighborhood ###
	
	#this version of GLASSgo_postprocessing excludes first input sequence
	#need to be duplicates_allowed=FALSE for normal run to create GLASSgo2Copra output
	cmd_neighbor = 'R --slave -f  ./scripts/GLASSgo_postprocessing_8_modi.r --args filename='+input_file+' duplicates_allowed=FALSE synteny_window=10000  name=testfile coprarna_compatible=FALSE ooi=NC_000964'
	ps=Popen(cmd_neighbor,shell=True,stdin=PIPE, stdout=PIPE, stderr=STDOUT, close_fds=True,encoding='utf8')
	output = ps.stdout.read()
	print(output)
	error=''
	if 'Error' in output:
		error+='Minor error was found in GLASSgo_postprocessing step'

	### calculate Phylo score and make weighted network ##
	remove_duplication_seq("16s_GenBank.fasta","16s_u.fasta")
	os.system('rm synteny.db')
	synteny2DB('testfile_synteny_table.txt','testfile_cluster_table.txt','16s_u.fasta')
	make_multiple_seq_align("16s_u.fasta")
	make_phylo_tree("16s_u.phy",'F')
	calculate_Phylo_score("synteny.db",3,neighborhood_weight) #database name , number of conserved genomes cutoff, weight score for network relationship
	make_network_input('testfile_cluster_table.txt', 'testfile_synteny_table.txt', 'nb_test.out', 'False') #
	convert_node2edge_weight('nb_test.out','Phylo_score.tab','Phylo_score_node2edge.csv') #neighbor relationship file, Phylo score file, output file ## for convert node weight to edge weight

	#make network file using pairwise GNN similarity score as weighted edges
	calculate_pairwise_network_similarity('Phylo_score_node2edge.csv','GNSN.csv')


	### for calculating pairwise similarity score between query sequences ###
	#remove_first_seq(input_file,input_file+'2') #first seq is query seq, in the case of normal version of GLASSgo , but not necessary for the modified version
	remove_duplication_seq("pass_glassgo2copra.fasta","u_pass_glassgo2copra.fasta")
	pairwise_ali_vsearch('u_pass_glassgo2copra.fasta',"pairwise2.csv") #pass_glassgo2copra.fasta is the fasta output file after Glassgo2copra
	#os.system('rm '+input_file+'2')
	convert_pairwise2weight("pairwise2.csv","query_label.out",query_weight,"pairwise2weight.csv") #output from alignment, weight score, query_label file, output

	### combine pairwise sequence similarity and GNSN
	combine_weight('GNSN.csv','pairwise2weight.csv','pairwise_GNSN.csv') #combine weight score from two file as average score
	print(error)

	#os.system('rm full_tree.Rdata distances.Rdata testfile_16S_tree.pdf coor.Rdata testfile_cluster_table.txt testfile_synteny_table.txt 16s.fasta 16s_subset.fasta 16s_GenBank.fasta 16s_aligned2.fasta 16s_aligned.fasta')


#FASTA_input=sys.argv[1]

#make_phylo_tree_GNN(FASTA_input, 0, 0)

#print(build_phylo_tree_from_similarity_file(FASTA_input, FASTA_input))
#print(make_pc_tree(FASTA_input+'.nw',FASTA_input))
#compare_tree('pairwise2weight.csv.nw','GNSN.csv.nw')


#################
#FASTA_input1=sys.argv[1]
#FASTA_input2=sys.argv[2]
#print(build_phylo_tree_from_similarity_file(FASTA_input1, FASTA_input1, True, ['q.8','q.5','q.6','q.7']))
#print(make_pc_tree(FASTA_input1+'.nw',FASTA_input1))

#print(build_phylo_tree_from_similarity_file(FASTA_input2, FASTA_input2))
#print(make_pc_tree(FASTA_input2+'.nw',FASTA_input2))

#compare_tree(FASTA_input1+'.nw',FASTA_input2+'.nw')

#### optimization of GLASSgo output
#FASTA_input='GLASSgo_tune_48_0.fasta'
#make_phylo_tree_GNN(FASTA_input, 0, 0)
#GA_tree(100,10,'pass_glassgo2copra.fasta') #generation,population size, fasta input file

#### optimization of Random walk
#FASTA_input='GLASSgo_tune_48_0.fasta'
#make_phylo_tree_GNN(FASTA_input, 0, 0)

