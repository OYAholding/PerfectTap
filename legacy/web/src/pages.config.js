/**
 * pages.config.js - Page routing configuration
 * 
 * This file is AUTO-GENERATED. Do not add imports or modify PAGES manually.
 * Pages are auto-registered when you create files in the ./pages/ folder.
 * 
 * THE ONLY EDITABLE VALUE: mainPage
 * This controls which page is the landing page (shown when users visit the app).
 * 
 * Example file structure:
 * 
 *   import HomePage from './pages/HomePage';
 *   import Dashboard from './pages/Dashboard';
 *   import Settings from './pages/Settings';
 *   
 *   export const PAGES = {
 *       "HomePage": HomePage,
 *       "Dashboard": Dashboard,
 *       "Settings": Settings,
 *   }
 *   
 *   export const pagesConfig = {
 *       mainPage: "HomePage",
 *       Pages: PAGES,
 *   };
 * 
 * Example with Layout (wraps all pages):
 *
 *   import Home from './pages/Home';
 *   import Settings from './pages/Settings';
 *   import __Layout from './Layout.jsx';
 *
 *   export const PAGES = {
 *       "Home": Home,
 *       "Settings": Settings,
 *   }
 *
 *   export const pagesConfig = {
 *       mainPage: "Home",
 *       Pages: PAGES,
 *       Layout: __Layout,
 *   };
 *
 * To change the main page from HomePage to Dashboard, use find_replace:
 *   Old: mainPage: "HomePage",
 *   New: mainPage: "Dashboard",
 *
 * The mainPage value must match a key in the PAGES object exactly.
 */
import ChallengeComplete from './pages/ChallengeComplete';
import Challenges from './pages/Challenges';
import DailyQuests from './pages/DailyQuests';
import DailyRewards from './pages/DailyRewards';
import DuelLobby from './pages/DuelLobby';
import DuelResults from './pages/DuelResults';
import Friends from './pages/Friends';
import Game from './pages/Game';
import GameOver from './pages/GameOver';
import GameSettings from './pages/GameSettings';
import Home from './pages/Home';
import Leaderboard from './pages/Leaderboard';
import Matchmaking from './pages/Matchmaking';
import ModeSelect from './pages/ModeSelect';
import Profile from './pages/Profile';
import Shop from './pages/Shop';
import Spectate from './pages/Spectate';
import SetUsername from './pages/SetUsername';
import __Layout from './Layout.jsx';


export const PAGES = {
    "ChallengeComplete": ChallengeComplete,
    "Challenges": Challenges,
    "DailyQuests": DailyQuests,
    "DailyRewards": DailyRewards,
    "DuelLobby": DuelLobby,
    "DuelResults": DuelResults,
    "Friends": Friends,
    "Game": Game,
    "GameOver": GameOver,
    "GameSettings": GameSettings,
    "Home": Home,
    "Leaderboard": Leaderboard,
    "Matchmaking": Matchmaking,
    "ModeSelect": ModeSelect,
    "Profile": Profile,
    "Shop": Shop,
    "Spectate": Spectate,
    "SetUsername": SetUsername,
}

export const pagesConfig = {
    mainPage: "Home",
    Pages: PAGES,
    Layout: __Layout,
};