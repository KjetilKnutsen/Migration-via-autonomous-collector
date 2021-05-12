import random, pickle, os

def weighted_choice(weights):
    totals = []
    running_total = 0

    for w in weights:
        running_total += w
        totals.append(running_total)

    rnd = random.random() * running_total
    for i, total in enumerate(totals):
        if rnd < total:
            return i
            


n=len(open("./hosts.txt").readlines(  )) #number of hosts to monitor
reward=[0]*n
lamda=0.15  #learning parameter, between 0 and 1.

pmax=0.98  #barrier, limit that any probablity will not exceed

pmin=(1-pmax)/(n-1)

#if one is pmax, while the rest, n-1 are at pmin, then the prob will sum to 1. pmax+(n-1)*pmin=pmax+(n-1)*(1-pmax)/(n-1)=1


if os.path.exists("./bin/pickle.p"):
    prob = pickle.load(open("./bin/pickle.p","rb"))
    p = prob[0]
    max_change = pickle.load(open("./bin/pickle.m","rb"))

if not os.path.exists("./bin/pickle.p"):
    p=[1.0/n]*n
    max_change = 0

chosen_index=weighted_choice(p) #p is probablity, roulettte wheel
#chosen_index=the host that we need to vist.
file = open("./bin/calc", "rt")
contents = file.read()

change_chosen=int(contents)  #this needs to be computed based on amount of change, since last visit (absolute value)

if change_chosen>max_change:
    max_change=change_chosen  #to keep track of max change for normalization


#updating the prob of the chosen wesite, we will increase the prpb of the chosen host in a proportional manner to the amount of change
p[chosen_index]=p[chosen_index]+lamda*(change_chosen/max_change)*(pmax-p[chosen_index])

#I will reduce the prob for all hosts that were not chosen, bcs I inreased the prob of the chosen.
for k in range(0,n):
        
    if (k!=chosen_index):
            
        p[k]=p[k]+lamda*(change_chosen/max_change)*(pmin-p[k]) #note (pmin-p[k]) is negative
     

            
    
#print "iteration", i
print(p)
print(chosen_index+1)

pickle.dump([p], open("./bin/pickle.p", "wb"))
pickle.dump(max_change, open("./bin/pickle.m", "wb"))
