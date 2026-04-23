import './styles.css';
import { App } from './core/App';
import { LotusLake } from './levels/LotusLake';
import { FireflyForest } from './levels/FireflyForest';
import { ConstellationTrace } from './levels/ConstellationTrace';
import { DualFireflies } from './levels/DualFireflies';
import { StormSwallow } from './levels/StormSwallow';
import { MeteorTrial } from './levels/MeteorTrial';

const app = new App();
app.registerLevel(0, new LotusLake());
app.registerLevel(1, new FireflyForest());
app.registerLevel(2, new ConstellationTrace());
app.registerLevel(3, new DualFireflies());
app.registerLevel(4, new StormSwallow());
app.registerLevel(5, new MeteorTrial());
app.start();
