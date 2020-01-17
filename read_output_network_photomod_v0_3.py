#!/usr/bin/env python
import argparse
import sys,os
import random
from subprocess import call

## version
# 0.3 -- make a new html file for the new outout (method: copy_html_output_template)
#     -- add capture network option
# 0.2 -- coloring query nodes by given taxa

def clamp(val, minimum=0, maximum=255):
    if val < minimum:
        return int(minimum)
    if val > maximum:
        return int(maximum)
    return int(val)

def colorscale(hexstr, scalefactor):
    hexstr = hexstr.strip('#')

    if scalefactor < 0 or len(hexstr) != 6:
        return hexstr
    r, g, b = int(hexstr[:2], 16), int(hexstr[2:4], 16), int(hexstr[4:], 16)
    r = 255
    g = clamp(g * scalefactor)
    b = clamp(b * scalefactor)
    return "#%02x%02x%02x" % (r, g, b)
#usafe :colorscale("#fff0f0", 1.0) #lower score -> more red color

def copy_html_output_template(html_template,file_output_name):
	file_html_out=file_output_name+'.html'
	call('cp '+html_template+' ./'+file_html_out,shell=True)
	call('sed s/"XXXjs_file_XXX"/"'+file_output_name+'.js"/g '+html_template+' > '+file_html_out,shell=True)
	call('sed -i s/"XXXtree_pngXXX"/"'+file_output_name+'_tree.png"/g '+file_html_out,shell=True)
	call('mv label_tree.png '+file_output_name+'_tree.png',shell=True)

def print_html(network_file,quey_file,neighbor_file,js_file):

	q_id=[]
	n_id=[]
	edg=[]
	all_phylo=[]
	dict_N={}
	dict_Q={}
	#### preprocess #####
	network_file=open(network_file,'r')
	call_outputfile=network_file.read().split('\n')
	network_file.close()
	eva=10

	for k in open(quey_file): #query file contain 7 columns #ID,Name,Locus,Accession,RefSeq,TaxID,node_color_code
		k=k.rstrip()
		if k != '' and ('#' not in k[0]):
			col_k=k.split(',')
			dict_Q[col_k[0]]=[col_k[1],col_k[2],col_k[3],col_k[4],col_k[5],col_k[6]]

	for k in open(neighbor_file): #neighbor file contain 7 columns
  #[0]cluster ID,[1]gene_id,[2]UniprotID,[3]gene_name,[4]Description,[5]GOterm,[6]P.ident
		k=k.rstrip()
		if k != '' and ('#' not in k):
			col_k=k.split(',')
			#print(col_k)
			if col_k[0] not in dict_N:
				dict_N[col_k[0]]=[[col_k[3],col_k[2],col_k[6],col_k[4],col_k[5]]]
			else:
				temp=dict_N[col_k[0]]
				temp.append([col_k[3],col_k[2],col_k[6],col_k[4],col_k[5]])
				del dict_N[col_k[0]]
				dict_N[col_k[0]]=temp	
	#### end preprocess #####

	for ind in call_outputfile:
		if ('#' not in ind) and (ind != ''):
			ind=ind.split(',')
			if ind[0] not in q_id:
				q_id.append(ind[0])

			if ind[1] not in n_id:
				n_id.append(ind[1])

			edg.append( [[ind[0]],[ind[1]],[ind[2]]] )
			all_phylo.append(float(ind[2]))


	w2js=open(js_file+'.js','w')
	w2js.write("""
function cyFunction"""+str(eva)+"""(){
	
    var options = {
      name: 'cola',

      animate: true, // whether to show the layout as it's running
      refresh: 1, // number of ticks per frame; higher is faster but more jerky
      maxSimulationTime: 4000, // max length in ms to run the layout
      ungrabifyWhileSimulating: false, // so you can't drag nodes during layout
      fit: false, // on every layout reposition of nodes, fit the viewport
      padding: 30, // padding around the simulation
      boundingBox: undefined, // constrain layout bounds; { x1, y1, x2, y2 } or { x1, y1, w, h }
      nodeDimensionsIncludeLabels: false, // whether labels should be included in determining the space used by a node

      // layout event callbacks
      ready: function(){}, // on layoutready
      stop: function(){}, // on layoutstop

      // positioning options
      randomize: false, // use random node positions at beginning of layout
      avoidOverlap: false, // if true, prevents overlap of node bounding boxes
      handleDisconnected: true, // if true, avoids disconnected components from overlapping
      convergenceThreshold: 0.01, // when the alpha value (system energy) falls below this value, the layout stops
      nodeSpacing: function( node ){ return 10; }, // extra spacing around nodes
      flow: undefined, // use DAG/tree flow layout if specified, e.g. { axis: 'y', minSeparation: 30 }
      alignment: undefined, // relative alignment constraints on nodes, e.g. function( node ){ return { x: 0, y: 1 } }
      gapInequalities: undefined, // list of inequality constraints for the gap between the nodes, e.g. [{"axis":"y", "left":node1, "right":node2, "gap":25}]

      // different methods of specifying edge length
      // each can be a constant numerical value or a function like `function( edge ){ return 2; }`
      edgeLength: undefined, // sets edge length directly in simulation
      edgeSymDiffLength: undefined, // symmetric diff edge length in simulation
      edgeJaccardLength: undefined, // jaccard edge length in simulation

      // iterations of cola algorithm; uses default values on undefined
      unconstrIter: undefined, // unconstrained initial layout iterations
      userConstIter: undefined, // initial layout iterations with user-specified constraints
      allConstIter: undefined, // initial layout iterations with all constraints including non-overlap

      // infinite layout options
      infinite: false // overrides all other options for a forces-all-the-time mode
    };

    var cy = cytoscape({
      container: document.getElementById('cy"""+str(eva)+"""'),
      elements: [
        // nodes\n""")

	for q_ind in q_id:
		w2js.write("        { data: { id: '"+str(q_ind)+"' , name: \'"+str(q_ind)+"\'}, classes: 'query'  },\n")
		#w2js.write("        { data: { id: '"+str(q_ind)+"' , name: \'"+str(dict_Q[q_ind][0])+"\'}, classes: 'query'  },\n") ## to use org name instead of q.ID

	for n_ind in n_id:
		if n_ind in dict_N:
			max_n_ind=max(dict_N[n_ind], key=lambda item: item[2])
			nname=max_n_ind[0]
		else:
			nname=n_ind
		w2js.write("        { data: { id: '"+str(n_ind)+"' , name: \'"+str(nname)+"\'}, classes: 'neighbor'  },\n")	

	w2js.close()

	w2js=open(js_file+'.js','a')

	for x in edg:
		w2js.write(
		"""
	    {
	      data: {
	        id: '%(S)s_%(T)s',
	        source: '%(S)s',
	        target: '%(T)s'
	      }
	    },\n""" % {'S': str(x[0][0]), 'T':str(x[1][0])})


	w2js.write(
	"""
	  ],
      style: [
        {
          selector: 'node',
          style: {
            shape: 'circle',
            'background-color': '#E7E7E7',
            label: 'data(name)',
            'text-valign': 'center',
				'text-halign': 'center',
				'border-width': 2,
				'border-color': 'black',
				'opacity': 0.7,


            }

        },
        {
          selector: 'edge',
          style: {
          	'curve-style': 'bezier',
	        'width': 3,
	        'line-color': '#BDBDBD',
	        'opacity': 0.5

            }
        },\n""")
	for q_ind in q_id: ### to assign color code to query nodes

		w2js.write("""
        {
          selector: 'node[id = "%(N)s"]',
          style: {
          	shape: 'hexagon',
            'color': 'blue',
            'background-color': '%(R)s',
            'background-opacity': 0.8,
            }
        },\n""" % {'N': q_ind, 'R': str(dict_Q[q_ind][5])})

	min_all_phylo=min(all_phylo)
	max_all_phylo=max(all_phylo)
	for n_ind in n_id: 
		#### for random color code , use color gradien instead ####
		#r = lambda: random.randint(0,255)
		#code_color= '#%02X%02X%02X' % (r(),r(),r())
		#print code_color
		##############################

		#search for maximum phylo score for display in the network
		max_phylo=0.0
		for phy in edg:
			if n_ind == phy[1][0] : #phy[1] is neighboring cluster ID
				current_phylo=float(phy[2][0])
				if current_phylo > max_phylo:
					max_phylo=current_phylo
		#print max_phylo
		#setting node size
		if max_phylo < 10.0:
			h_node=30
			w_node=30
		else:
			h_node=3.0*max_phylo
			w_node=3.0*max_phylo


		####### for color gradient #######
		if max_all_phylo == min_all_phylo:
			norm_phylo_score=0.0
		else:
			norm_phylo_score= (max_phylo - min_all_phylo) / (max_all_phylo-min_all_phylo)
		scale_color_code=1.0-norm_phylo_score
		code_color = colorscale("#fff0f0", scale_color_code)
		####### end color gradient #######

		w2js.write("""
        {
          selector: 'node[id = "%(N)s"]',
          style: {
            shape: 'circle',
            height: %(H)s,
            width: %(W)s,
            'background-color': '%(R)s',
            'background-opacity': 0.8,
            label: 'data(name)'
            }

        },\n""" % {'R': code_color, 'N': n_ind, 'H': str(h_node), 'W': str(w_node)})

	w2js.write("""
        ]
    },);
	cy.layout( options );\n""")

	for idF in dict_N: #write neighbor node description
		
		max_idF=max(dict_N[idF], key=lambda item: item[2]) #select only best identity score to display

		w2js.write("""

	// for node description
    cy.elements('node[id = \""""+str(idF)+"""\"]').qtip({
              content: {
              text: 'Cluster ID : """+str(idF)+""" <br>Gene : """+str(max_idF[0])+""" <br>Uniprot ID : <a href="https://www.uniprot.org/uniprot/"""+str(max_idF[1])+"""\">"""+str(max_idF[1])+"""</a><br> %ident max : """+str(max_idF[2])+""" <br>Description : """+str(max_idF[3])+""" <br>GO terms : """+str(max_idF[4])+"""',         
              },
              position: {
                my: 'top center',
                at: 'bottom center'
              },
              show: {
                cyBgOnly: true
              },
              style: {
                classes: 'qtip-bootstrap',
                tip: {
                  width: 16,
                  height: 8
                }
              }
            });\n""")

	for idF in dict_Q:  #write query node description
		w2js.write("""

	// for node description
    cy.elements('node[id = \""""+str(idF)+"""\"]').qtip({
              content: {
              text: '"""+str(dict_Q[idF][0])+""" <br>Locus : """+str(dict_Q[idF][1])+"""<br>Accession : """+str(dict_Q[idF][2])+"""<br>RefSeq : """+str(dict_Q[idF][3])+"""',         
              },
              position: {
                my: 'top center',
                at: 'bottom center'
              },
              show: {
                cyBgOnly: true
              },
              style: {
                classes: 'qtip-bootstrap',
                tip: {
                  width: 16,
                  height: 8
                }
              }
            });\n""") 

	w2js.write("""

	cy.on("tap", "node", (evt) => {
	evt.cyTarget.connectedEdges().animate({
	style: {lineColor: "red"}

	})
	}
	);

	cy.on("tap", "node", (evt) => {
	evt.cyTarget.connectedEdges().animate({
	style: {lineColor: "black",opacity: 0.5}

	})
	}
	);

	cy.layout( options );
	
	$('#clickMe_"""+str(eva)+"""').click(function () {
	    var png64 = cy.png({
	    	
	    	maxWidth: 4000,
	    	maxHeight: 3000
	    });
	    // put the png data in an img tag
	    $('#png-e"""+str(eva)+"""').attr('src', png64);

	});		

};""")

	w2js.close()


#network_file,quey_file,neighbor_file,call_outputfile
print_html(sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4])
copy_html_output_template('./assets_photomod/result_network_photomod_template.html',sys.argv[4])


#usage
#python ../script/read_output_network_photomod_v0_2.py node2edge.cy mapping.q mapping.n test.js
