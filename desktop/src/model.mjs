export const wrap=(index,count)=>count>0?((index%count)+count)%count:null;
export const offsets=count=>count===0?[]:count===1?[0]:[-3,-2,-1,0,1,2,3];
export function slots(position,games){return offsets(games.length).map(offset=>({key:position+offset,offset,game:games[wrap(position+offset,games.length)]}));}
export function nearestPosition(position,index,count){if(!count)return 0;const current=wrap(position,count);let delta=index-current;if(delta>count/2)delta-=count;if(delta< -count/2)delta+=count;return position+delta;}
export function filterGames(games,filter,query){const term=query.toLocaleLowerCase();return games.filter(g=>!g.hidden&&(filter==='All games'||filter==='Favorites'&&g.favorite||filter==='Recently played'&&g.lastPlayed||g.store===filter)&&(!term||g.name.toLocaleLowerCase().includes(term)||(g.genres||[]).some(s=>s.toLocaleLowerCase().includes(term)))).sort((a,b)=>filter==='Recently played'?(b.lastPlayed||0)-(a.lastPlayed||0):a.name.localeCompare(b.name));}
export const imageRole=(game,role)=>game.images?.[role]??(role==='background'?game.images?.landscape:null)??game.images?.portrait??null;
export const direction=(x,dpadLeft,dpadRight)=>dpadLeft?-1:dpadRight?1:x<-.55?-1:x>.55?1:0;
